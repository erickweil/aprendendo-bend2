# Aprendendo Bend 2

Repositório dedicado ao estudo aprofundado, benchmarking, provas formais e engenharia de algoritmos de alta performance na linguagem **Bend 2 (2.0.5)**, desenvolvida pela [HigherOrderCO](https://higherorderco.com/).

O Bend 2 combina a expressividade funcional do Haskell, a clareza sintática do Python, a verificação formal de teoremas do Lean/Coq e o paralelismo massivo em hardware moderno (CPUs multi-core e GPUs) baseado na arquitetura de Redes de Interação da **HVM (High-order Virtual Machine)**.

---

## 📑 Sumário

- [1. Instalação e Configuração do Toolchain](#1-instalação-e-configuração-do-toolchain)
- [2. Principais Conceitos e Descobertas da Linguagem](#2-principais-conceitos-e-descobertas-da-linguagem)
  - [2.1 Tipos de Dados Algébricos (ADTs) e Desestruturação](#21-tipos-de-dados-algébricos-adts-e-desestruturação)
  - [2.2 Modelo de Redução e Paralelismo Implícito](#22-modelo-de-redução-e-paralelismo-implícito)
  - [2.3 Anotações de Variáveis: Linearidade (`+`) e Erased (`~`)](#23-anotações-de-variáveis-linearidade--e-erased-)
  - [2.4 Provas Formais e Teoremas Matemáticos](#24-provas-formais-e-teoremas-matemáticos)
  - [2.5 Compilação para C e Binários Nativos](#25-compilação-para-c-e-binários-nativos)
- [3. Arquitetura do Motor Genético e Solver de Horários](#3-arquitetura-do-motor-genético-e-solver-de-horários)
  - [3.1 Estrutura em Árvore Binária (PopTree)](#31-estrutura-em-árvore-binária-poptree)
  - [3.2 PRNG Puro com Seed-Splitting](#32-prng-puro-com-seed-splitting)
  - [3.3 Parser e Serializador JSON Nativo (json.bend)](#33-parser-e-serializador-json-nativo-jsonbend)
  - [3.4 Solver Dinâmico de Horários (100% JSON)](#34-solver-dinâmico-de-horários-100-json)
- [4. Benchmarks e Escalabilidade Multi-Core](#4-benchmarks-e-escalabilidade-multi-core)
- [5. Guias e Documentação Especializada](#5-guias-e-documentação-especializada)

---

## 1. Instalação e Configuração do Toolchain

Seguindo o guia oficial em [bend-lang.com](https://bend-lang.com/):

```bash
curl -fsSL https://bend-lang.com/install.sh | sh
```

Para garantir operação limpa e sem envio de métricas de rede no terminal:
```bash
export BEND_NO_TELEMETRY=1
export PATH="$HOME/.toolchain/bend/bin:$PATH"
```

Comandos essenciais da CLI:
```bash
# Verifica a versão
bend --version

# Exibe o manual e guia completo de sintaxe
bend guide

# Executa um arquivo diretamente via interpretador JIT/FFI
bend arquivo.bend

# Compila para binário nativo standalone em C (requer clang/gcc)
bend arquivo.bend -o bin_executavel

# Emite o código-fonte C gerado sem compilar
bend arquivo.bend -o saida.c

# Verifica todas as leis, provas formais e tipos do arquivo
bend arquivo.bend --checkup
```

---

## 2. Principais Conceitos e Descobertas da Linguagem

### 2.1 Tipos de Dados Algébricos (ADTs) e Desestruturação
Os tipos de dados são declarados com `type Nome is Data:` e podem conter um ou múltiplos construtores:

```bend
type Day4 is Data:
  D4{t0: U32, t1: U32, t2: U32, t3: U32}

def Day4.get(d: Day4, +idx: U32) -> U32:
  D4{t0, t1, t2, t3} = d
  Bool.pick(U32, U32.is_lt(idx, 2),
    Bool.pick(U32, U32.is_eq(idx, 0), t0, t1),
    Bool.pick(U32, U32.is_eq(idx, 2), t2, t3))
```

> **Dica de Engenharia:** Em Bend 2, a checagem de tipos é bidirecional. Sempre que instanciar um ADT em expressões com escopo local, prefira criar uma função auxiliar construtora tipada (ex: `def make_d4(...) -> Day4: D4{...}`), eliminando ambiguidades do verificador de tipos.

### 2.2 Modelo de Redução e Paralelismo Implícito
O Bend paraleliza automaticamente tarefas ramificadas quando dois termos são avaliados lado a lado na mesma linha:

```bend
# O runtime da HVM bifurca a execução em paralelo nos dois ramos
l r = eval_tree(left) eval_tree(right)
Node{l, r}
```
Não há mutexes, semáforos nem condições de corrida (*race conditions*): por operar sobre combinadores de interação matematicamente confluentes, o resultado é **determinístico** independente da ordem de agendamento das threads.

### 2.3 Anotações de Variáveis: Linearidade (`+`) e Erased (`~`)
- **`+var` (Linear / Duplicável):** Indica que a variável pode ser consumida mais de uma vez ou duplicada explicitamente.
- **`~var` (Erased / Compile-time):** Argumento estático ou de tipo avaliado em tempo de compilação e apagado no binário final.
- **`-var` (Inferido):** Parâmetro de tipo inferido.

### 2.4 Provas Formais e Teoremas Matemáticos
O Bend permite formalizar lemas e leis que o compilador verifica formalmente com `bend PROOF.bend`:

```bend
law IdempotentXor(x: U32):
  (x ^ x) == 0
```
Nosso motor genético possui 22 leis formais verificadas e aprovadas com 100% de precisão.

### 2.5 Compilação para C e Binários Nativos
Compilar o Bend para C gera binários de altíssimo desempenho:
```bash
bend genetic/src/horario_solver.bend -o horario_bin
./horario_bin --threads 4
```
No problema real de horários escolares com 400 gerações, o binário nativo executou em apenas **93 milissegundos**, superando o interpretador CLI em mais de 60 vezes.

---

## 3. Arquitetura do Motor Genético e Solver de Horários

O diretório `genetic/` contém um motor genético de última geração projetado especificamente para tirar proveito da arquitetura HVM.

```text
genetic/
├── ga.bend                # Motor de Algoritmo Genético em Árvore & Modelo de Ilhas
├── operators.bend         # 26 operadores genéticos (OX1, PMX, 2-Opt, Bitwise, etc.)
├── PROOF.bend             # 22 provas formais das leis matemáticas
├── bench_cpus.py          # Benchmark multi-core (1, 2, 4, 8 CPUs)
├── data/
│   └── horario_input.json # Dataset de teste real (FormularioHorario)
├── utils/
│   ├── json.bend          # Parser e Serializador JSON reutilizável em Bend puro
│   ├── poptree.bend       # Estrutura de árvore de população balanceada
│   └── random.bend        # PRNG puro Xorshift32 com seed-splitting
└── src/
    ├── horario_solver.bend # Solver dinâmico de horário escolar (100% orientado a JSON)
    └── scenario1_onemax.bend a scenario18_*.bend
```

### 3.1 Estrutura em Árvore Binária (`PopTree`)
A população não é um vetor plano sequencial, mas uma árvore balanceada de profundidade $D$ com $2^D$ indivíduos:
- **Redução paralela:** A busca do campeão e as estatísticas agregadas são calculadas em $O(\log N)$ passos paralelos.
- **Elitismo estrito de passagem única:** A população da próxima geração e o novo campeão são gerados em uma única travessia sem reinserção redundante.

### 3.2 PRNG Puro com Seed-Splitting
Em vez de depender de estado global mutável, o gerador de números aleatórios é 100% funcional (Xorshift32 puro). Para ramificações em árvore:
```bend
l r = build_tree(p, R.split.fst(seed)) build_tree(p, R.split.snd(seed))
```
Gera fluxos estatisticamente independentes sem bloqueios nem contenção de memória cache.

### 3.3 Parser e Serializador JSON Nativo (`json.bend`)
Desenvolvemos uma biblioteca reutilizável e completa de manipulação de JSON em Bend puro:
- **AST:** Representação limpa em `JNull`, `JBool`, `JNum`, `JStr`, `JArr` e `JObj`.
- **Parsing:** Analisador léxico e sintático recursivo sem dependências externas.
- **Consultas Seguras:** `Json.get`, `Json.get_str`, `Json.get_num`, `Json.get_arr`.
- **Serialização:** `Json.stringify` com formatação compatível com JSON RFC 8259.

### 3.4 Solver Dinâmico de Horários (100% JSON)
O solver unificado [`horario_solver.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/src/horario_solver.bend) implementa:
1. **Zero Mapeamentos Fixos:** Nenhum nome de turma, disciplina ou professor é embutido no código. Tudo é extraído em runtime a partir do JSON fornecido via variável de ambiente `HORARIO_JSON`.
2. **Tabelas Planas O(1) (`Table16` e `Table32`):** As associações entre disciplinas e professores e as matrizes de indisponibilidade semanal são compactadas em tabelas numéricas planas de `U32`, eliminando alocações na HVM durante as centenas de gerações evolutivas.
3. **Regras 1:1 com o Sistema Original em Rust:**
   - Detecção de choques de professores entre turmas no mesmo período.
   - Verificação de indisponibilidade semanal via máscaras de 20 bits.
   - Sincronização estrita de disciplinas unidas (ex: turmas diferentes cursando aulas acopladas juntas).
   - Agrupamento ótimo de aulas consecutivas em blocos de 2 períodos.
4. **Saída Estruturada:** Serialização da melhor grade horária diretamente para o padrão `TurmaHorarioResult[]`.

---

## 4. Benchmarks e Escalabilidade Multi-Core

Resultados obtidos com o dataset real de 3 turmas, 20 disciplinas e 10 professores ([`bench_cpus.py`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/bench_cpus.py)):

### ⚡ Binário Nativo C (`bend -o horario_bin`) — 400 Gerações
| Núcleos / Configuração | Média de Tempo | Desvio |
| :--- | :---: | :---: |
| **1 CPU (taskset -c 0)** | **92.9 ms** | $\pm 7$ ms |
| **2 CPUs (taskset -c 0,1)** | **97.4 ms** | $\pm 6$ ms |
| **4 CPUs (taskset -c 0-3)** | **95.2 ms** | $\pm 2$ ms |
| **Sem taskset (default OS)** | **93.4 ms** | $\pm 1$ ms |

> O binário compilado em C realiza o parsing completo do JSON, carrega a especificação dinâmica, roda 400 gerações de algoritmo genético e serializa o JSON final em **menos de 0,1 segundo**.

### 🚀 Interpretador Bend 2 CLI — 200 Gerações (Escalabilidade de CPU)
| Núcleos / Configuração | Média de Tempo | Speedup Obtido |
| :--- | :---: | :---: |
| **1 CPU (taskset -c 0)** | 5578 ms | 1.00x (Baseline) |
| **2 CPUs (taskset -c 0,1)** | 3001 ms | **1.86x** |
| **4 CPUs (taskset -c 0-3)** | 2358 ms | **2.36x** |

A avaliação paralela da árvore de população (`PopTree`) escala naturalmente conforme núcleos adicionais de CPU são disponibilizados ao runtime.

---

## 5. Guias e Documentação Especializada

- 🤖 [**AGENTS.md**](file:///home/ubuntu/claude/aprendendo-bend2/AGENTS.md): Guia obrigatório para agentes de IA com as armadilhas críticas da HVM (closures afins, `Bool.pick` estrito, explosão de nós DUP, Peano Nats) e regras de segurança para evitar 100% de CPU ou OOM.
- 🧬 [**genetic/README.md**](file:///home/ubuntu/claude/aprendendo-bend2/genetic/README.md): Documentação detalhada dos 18 cenários genéticos, operadores formais e modelo de ilhas (PGA).
- 📊 [**benchmarks/REPORT.md**](file:///home/ubuntu/claude/aprendendo-bend2/benchmarks/REPORT.md): Relatório comparativo de benchmarks do compilador.