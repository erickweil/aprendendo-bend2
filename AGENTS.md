# AGENTS.md — Guia de Engenharia e Operação em Bend 2

Este documento serve como a bíblia técnica e manual de sobrevivência para **agentes de IA** (Claude Code, Antigravity, etc.) e desenvolvedores humanos que mantêm ou expandem a base de código do repositório `aprendendo-bend2`.

---

## 0. Regras de Ouro e Diretrizes do Ambiente

1. **Escopo Restrito:** Trabalhe **exclusivamente** dentro de `~/claude/` (e em particular dentro deste repositório `~/claude/aprendendo-bend2/`).
2. **Versionamento e Git:** 
   - A branch ativa de trabalho é `feature/motor-genetico`.
   - Faça `git push origin feature/motor-genetico` **a cada commit** (autorização explícita do usuário).
   - Verifique sempre `git diff` antes de commitar para garantir que nenhum arquivo temporário ou artefato de build foi incluído.
3. **Telemetria:** Sempre defina `export BEND_NO_TELEMETRY=1` ao invocar o compilador/runtime do Bend.
4. **Toolchain Oficial:** Utilize o executável local do Bend 2:
   ```bash
   /home/ubuntu/claude/.toolchain/bend/bin/bend
   ```

---

## 1. Como Orquestrar a Execução do Bend 2 com Segurança

Nas versões modernas do Bend 2 (construídas sobre a HVM — High-order Virtual Machine), o runtime reduz redes de interação (*interaction combinators*) de forma preguiçosa e paralela. Se o código for mal projetado, ele pode entrar em ciclos de reescrita infinita ou expansão exponencial de nós de duplicação (`dup`), **consumindo 100% de CPU em todos os núcleos e gerando Out-Of-Memory (OOM)** que força o kernel Linux a encerrar processos e sessões inteiras.

### 1.1 Comandos de Execução Segura

* **Sempre utilize `timeout`:** Nunca execute `bend` diretamente sem um limite de tempo.
  ```bash
  export BEND_NO_TELEMETRY=1
  timeout 30s /home/ubuntu/claude/.toolchain/bend/bin/bend <arquivo.bend>
  ```
* **Controle de Threads na Compilação C:**
  O Bend compila para C puro via `-o`:
  ```bash
  bend arquivo.bend -o bin_executavel
  # Execução controlada:
  ./bin_executavel --threads 1     # Single core (seguro para debug)
  ./bin_executavel --threads 4     # Multi core calibrado
  ```
* **Compilação e Verificação Estática:**
  - Verificação de tipos/sintaxe: `bend <arquivo.bend>` (compila e executa o `main`).
  - Verificação de provas e teoremas: `bend <arquivo.bend> --checkup` ou `bend PROOF.bend`.
  - Inspeção do código gerado: `bend <arquivo.bend> -o saida.c` (emite o fonte C sem compilar).

---

## 2. As Armadilhas Críticas da Linguagem Bend 2

Compreender estas 6 armadilhas é fundamental para programar em Bend 2 sem travar o compilador ou estourar a memória da VM:

### 🔴 Armadilha 1: Closures são Afins (*Affine Closures*)
> **Conceito:** Em Bend 2, uma função anônima que captura variáveis do escopo (`x => f(x, capturado)`) é **afim** (*affine*): ela só pode ser chamada **no máximo uma vez**.

* **O Erro:** Passar uma closure com estado capturado para uma função que repete chamadas (como um loop genético `run_generations`, um fold ou map). O compilador rejeitará com erro de afinidade ou travará em tempo de compilação.
* **A Solução:**
  1. Use apenas definições de topo (*top-level definitions*) como funções de ordem superior.
  2. Passe os dados capturados explicitamente como parte do genoma/indivíduo (`Cand`), ou empacote parâmetros em registros puros unboxed.

---

### 🔴 Armadilha 2: `Bool.pick` é Estrito (*Strict Evaluation*)
> **Conceito:** Na HVM, `Bool.pick(T, cond, then_branch, else_branch)` avalia **ambos os ramos** incondicionalmente.

* **O Erro:** Chamar recursão dentro de um ramo do `Bool.pick`:
  ```bend
  # ❌ INCORRETO: Recurse em loop infinito porque o ramo da recursão SEMPRE é avaliado!
  def find(l, target):
    match l:
      case Nil{}: 0
      case h <> t: Bool.pick(U32, is_eq(h, target), 1, find(t, target))
  ```
* **A Solução:** Para bifurcações com recursão ou efeitos, isole a checagem em uma função auxiliar de passo (`.step`) com `match` em um booleano:
  ```bend
  # ✔️ CORRETO: O pattern match no booleano descarta o ramo não tomado sem avaliá-lo!
  def find.step(is_match: Bool, t: List, target: U32) -> U32:
    match is_match:
      case True{}: 1
      case False{}: find(t, target)

  def find(l: List, target: U32) -> U32:
    match l:
      case Nil{}: 0
      case h <> t: find.step(is_eq(h, target), t, target)
  ```
  *(Nota: `Bool.pick` entre números primitivos escalares `U32` é seguro e extremamente rápido, funcionando como um `cmov` em hardware).*

---

### 🔴 Armadilha 3: Explosão de Nós DUP em Redes de Interação (Causa de OOM)
> **Conceito:** A HVM não possui coletor de lixo convencional baseado em tracing; ela opera por aniquilação e duplicação de nós em grafos de interação.

* **O Erro:** Colocar estruturas de dados baseadas em ponteiros (como `List<&2, String>`, `List<&2, U32>`, ou árvores profundas) dentro de tipos que sofrem clonagem repetida (como genomas ou indivíduos dentro de um loop de 400 gerações).
  - Cada crossover, mutação ou seleção de elite duplica a lista encadeada inteira, gerando árvores exponenciais de nós `dup`.
  - A RAM é consumida rapidamente em poucos segundos até acionar o OOM Killer.
* **A Solução:**
  - O **genoma quente** de um algoritmo genético deve conter **exclusivamente números primitivos unboxed** (`U32`) agrupados em structs planas (ex: `Day4`, `Week5`, `Quadro3`).
  - Metadados, strings e nomes devem residir fora do loop evolutivo, sendo consumidos na entrada (parsing) e na saída (serialização).
  - Para tabelas dinâmicas de consulta no hot-path, use estruturas planas indexadas por bits como `Table16` e `Table32` (ver Seção 3).

---

### 🔴 Armadilha 4: O Custo Oculto de `Nat` e `U32.to_nat`
> **Conceito:** Em Bend 2, `Nat` é um número de Peano indutivo (`0n`, `1n+p`).

* **O Erro:** Chamar `List.get(&2, T, list, U32.to_nat(idx))` repetidamente dentro de um loop quente de fitness.
  - `U32.to_nat(20)` aloca 20 nós de Peano na memória para CADA leitura.
  - Multiplicado por 60 slots $\times$ 32 indivíduos $\times$ 400 gerações = dezenas de milhões de alocações desnecessárias.
* **A Solução:** Use vetores/tabelas planas com acesso bitwise $O(1)$ nativo em `U32`.

---

### 🔴 Armadilha 5: Inferência de Tipos em Construtores (`make_*`)
> **Conceito:** O sistema de tipos bidirecional do Bend 2 exige contexto de tipo para construtores ADT.

* **O Erro:**
  ```bend
  +cand = CD{q, spec}   # ❌ Erro: "expected: an annotated term (cannot infer)"
  ```
* **A Solução:** Crie pequenas funções construtoras com anotação explícita de retorno:
  ```bend
  def make_cand(q: Quadro3, spec: FastSpec) -> Cand:
    CD{q, spec}

  +cand = make_cand(q, spec)  # ✔️ O compilador infere perfeitamente
  ```

---

### 🔴 Armadilha 6: Restrições de Scrutinee no `match`
> **Conceito:** Em Bend 2, a instrução `match` só pode analisar diretamente **parâmetros de função ou campos desestruturados**.

* **O Erro:**
  ```bend
  match U32.is_gt(x, 0): # ❌ Erro: match cannot scrutinize a computed value
  ```
* **A Solução:** Passe a expressão computada para uma função `.step`:
  ```bend
  def is_positive.step(cond: Bool, x: U32) -> String:
    match cond:
      case True{}: "Positivo"
      case False{}: "Zero ou Negativo"

  def is_positive(x: U32) -> String:
    is_positive.step(U32.is_gt(x, 0), x)
  ```

---

## 3. Padrões Arquiteturais Recomendados

### 3.1 Tabelas de Acesso $O(1)$ sem Alocação (`Table16` e `Table32`)
Para armazenar configurações lidas de JSON que precisam ser consultadas milhares de vezes no loop genético (ex: qual o professor de cada matéria, ou qual a máscara de indisponibilidade de cada professor):

```bend
type Table16 is Data:
  T16{
    x0: U32, x1: U32, x2: U32, x3: U32,
    x4: U32, x5: U32, x6: U32, x7: U32,
    x8: U32, x9: U32, x10: U32, x11: U32,
    x12: U32, x13: U32, x14: U32, x15: U32
  }

def Table16.get(t: Table16, +idx: U32) -> U32:
  T16{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15} = t
  Bool.pick(U32, U32.is_lt(idx, 8),
    Bool.pick(U32, U32.is_lt(idx, 4),
      Bool.pick(U32, U32.is_lt(idx, 2),
        Bool.pick(U32, U32.is_eq(idx, 0), x0, x1),
        Bool.pick(U32, U32.is_eq(idx, 2), x2, x3)),
      Bool.pick(U32, U32.is_lt(idx, 6),
        Bool.pick(U32, U32.is_eq(idx, 4), x4, x5),
        Bool.pick(U32, U32.is_eq(idx, 6), x6, x7))),
    Bool.pick(U32, U32.is_lt(idx, 12),
      Bool.pick(U32, U32.is_lt(idx, 10),
        Bool.pick(U32, U32.is_eq(idx, 8), x8, x9),
        Bool.pick(U32, U32.is_eq(idx, 10), x10, x11)),
      Bool.pick(U32, U32.is_lt(idx, 14),
        Bool.pick(U32, U32.is_eq(idx, 12), x12, x13),
        Bool.pick(U32, U32.is_eq(idx, 14), x14, x15))))
```
*Vantagens:*
- Custo de leitura: 4 comparações branchless em hardware.
- Alocação no heap durante a evolução: **ZERO bytes**.
- Pode ser duplicado (`+t`) sem nenhum overhead em redes de interação.

### 3.2 Máscaras Bitwise para Disponibilidade Semanal
Para calendários semanais (ex: 5 dias $\times$ 4 tempos = 20 períodos):
- 20 slots cabem inteiramente dentro de uma única palavra `U32` (de até 32 bits).
- Para checar se o professor $P$ está indisponível no slot $s$:
  ```bend
  +is_unavail = U32.and(U32.shrn(prof_mask, U32.to_nat(s)), 1)
  ```
- Operação instantânea em $O(1)$, eliminando varreduras de matrizes ou listas.

---

## 4. Estrutura do Código no Repositório

```text
aprendendo-bend2/
├── AGENTS.md                  # Este guia
├── README.md                  # Visão geral e introdução ao Bend 2
├── genetic/
│   ├── ga.bend                # Motor genético funcional com PopTree e PGA
│   ├── operators.bend         # 26 operadores genéticos formais provados
│   ├── PROOF.bend             # 22 provas formais das leis matemáticas
│   ├── bench_cpus.py          # Script de medição de escalabilidade multi-core
│   ├── data/
│   │   └── horario_input.json # Dataset de teste real (FormularioHorario)
│   ├── utils/
│   │   ├── json.bend          # Parser e Serializador JSON reutilizável
│   │   ├── poptree.bend       # ADT PopTree e combinadores
│   │   └── random.bend        # PRNG puro Xorshift32 com seed-splitting
│   ├── src/
│   │   ├── horario_solver.bend # Solver dinâmico 100% orientado a JSON
│   │   ├── scenario1_onemax.bend a scenario18_*.bend
│   └── tests/
│       ├── json_test.bend     # Testes do parser JSON
│       ├── operators_test.bend# Testes exaustivos dos operadores
│       └── dynamic_test.bend  # Validação de extração dinâmica da AST JSON
```

---

## 5. Checklist de Verificação Antes de Enviar Commits

Sempre execute os passos abaixo antes de finalizar qualquer modificação:
```bash
export BEND_NO_TELEMETRY=1

# 1. Verificar provas formais
bend genetic/PROOF.bend

# 2. Executar testes de operadores e invariantes
bend genetic/tests/operators_test.bend

# 3. Executar teste do parser JSON
bend genetic/tests/json_test.bend

# 4. Executar o solver dinâmico com o dataset real
export HORARIO_JSON=$(cat genetic/data/horario_input.json)
bend genetic/src/horario_solver.bend

# 5. Commit e Push imediato
git commit -am "tipo(escopo): mensagem descritiva"
git push origin feature/motor-genetico
```
