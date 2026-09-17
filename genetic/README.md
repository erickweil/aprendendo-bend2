# Bend 2 - Solver Genético Paralelo em Árvore

Implementação completa e de alto desempenho de um motor de **Algoritmo Genético Paralelo** na linguagem **Bend 2 (2.0.4)**, remodelando e aprimorando a arquitetura original desenvolvida em Rust/TypeScript (`my-website/rust-wasm/src/genetic` e `horario`).

---

## 1. Avaliação Crítica da Implementação Anterior (`my-website`)

### 1.1 Acertos da Implementação Anterior
- **Invariantes Estruturais Preservadas por Construção**: No problema de horários, as disciplinas de uma turma foram modeladas como um multiconjunto fechado (`QuadroHorario`). Nenhuma mutação ou crossover atribuía disciplinas à turma errada nem alterava a carga horária semanal.
- **Operadores Especializados**: Uso de Order Crossover (OX1), IPX e amostragem de Poisson para passos de mutação.
- **Autodiagnóstico Preciso**: O documento `docs/plano-solver-local-search.md` já apontava o custo quadrático da população e a perda de desempenho pela falta de paralelismo em WASM single-thread.

### 1.2 Gargalos e Limitações da Implementação Anterior
- **Iteração Sequencial Monolítica**: A população (`Vec<Individual>`) era percorrida em um `for` sequencial em 1 núcleo de CPU, tornando populações maiores inviáveis.
- **Estado Global Mutável de RNG**: O gerador aleatório dependia de estado mutável global, impedindo computação paralela pura e sem locks.
- **Drift de Ponto Flutuante**: O fitness em `f64` exigia compensações com `+ f64::EPSILON`.
- **Fusão de Restrições Conflitantes**: Disponibilidade de professor e choque de turmas eram decrementados na mesma matriz (`prof_matriz`), mascarando o gradiente de penalidade.
- **Descarte Prematuro em Estagnação**: O reset completo da população descartava blocos de horários já solucionados.

---

## 2. Remodelagem para o Bend 2 e Paralelismo

A nova arquitetura explora os pontos fortes do Bend 2:

1. **População Estruturada em Árvore Binária (`PopTree`)**:
   - Cada população de $2^D$ indivíduos é uma árvore balanceada:
     ```bend
     type PopTree is Data:
       Leaf{ind: Ind}
       Node{left: PopTree, right: PopTree}
     ```
   - A avaliação de fitness dispara bifurcações paralelas automáticas pelo runtime do Bend:
     ```bend
     l r = eval_pop(left) eval_pop(right)
     Node{l, r}
     ```
2. **PRNG Determinístico Puro com Seed-Splitting**:
   - Baseado em **Xorshift32** puro, sem variáveis globais.
   - Para ramificações na árvore, a semente é bifurcada em $O(1)$:
     ```bend
     l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
     ```
   - Zero locks, zero contenção de memória, 100% determinístico e thread-safe.
3. **Fitness Exato em Inteiros (`U32`)**:
   - Zero tolerância/epsilon drift, execução direta no compilador C e GPU.
4. **Vizinhanças Inspiradas no Plano de Busca Local**:
   - `SwapSlot`: Ajuste fino intra-turma.
   - `SwapBloco`: Preserva agrupamento de aulas geminadas.
   - `SwapColuna`: Troca períodos em todas as turmas simultaneamente, preservando ausência de choques de professores.
   - `SwapBlocoColuna`: Reorganiza blocos inteiros sem quebrar agrupamento nem criar novos choques.

---

## 3. Os 5 Cenários Implementados

| Cenário | Descrição | Representação | Métrica Ótima | Resultado Obtido |
| :--- | :--- | :--- | :--- | :--- |
| **1. Bit Maxing (One-Max)** | Maximizar bits 1 em palavra de 32 bits | `U32` (32 genes binários) | 32 / 32 bits | **32 / 32 bits** (Ótimo) |
| **2. Ordenar Números** | Ordenar permutação de 8 números | `Perm8` (8 campos) | 28 / 28 pares | **[0, 1, 2, 3, 4, 5, 6, 7]** (Ótimo) |
| **3. Caixeiro Viajante (TSP)** | Rota fechada entre 8 cidades 2D | `Perm8` (ciclo fechado) | Distância = 240 | **Distância = 240** (Ótimo) |
| **4. Sudoku Solver** | Resolver grade 4x4 com pistas | `Board4` (16 células) | 0 conflitos | **0 conflitos** (Ótimo) |
| **5. Solver de Horário** | Grade de 2 turmas x 8 tempos, 3 profs, choques, indisponibilidade e blocos | `Timetable` (`Schedule8` x 2) | 0 penalidades | **0 penalidades** (Ótimo) |

---

## 4. Resultados e Tempos de Execução

Testado na VM (4 vCPUs AMD EPYC, Linux x86_64, Bend 2.0.4, Clang 19.1.1):

| Cenário | Tempo Interpretado (`bend`) | Tempo Compilado C (`-o`) | Solução Ótima Alcançada? |
| :--- | :---: | :---: | :---: |
| **1. Bit Maxing (One-Max)** | 0.357s | **0.016s** | **Sim (True)** |
| **2. Ordenar Números** | 0.452s | **0.020s** | **Sim (True)** |
| **3. Caixeiro Viajante (TSP)** | 0.521s | **0.037s** | **Sim (True)** |
| **4. Sudoku Solver** | 0.735s | **0.023s** | **Sim (True)** |
| **5. Solver de Horário Escolar** | 1.045s | **0.034s** | **Sim (True)** |

Todos os cenários compilados em C executam em **menos de 40 milissegundos**!

---

## 5. Como Executar

Para rodar toda a suite automatizada:

```bash
cd ~/claude/genetic-bend2
./run_all.sh
```

Para executar ou compilar um cenário individual:

```bash
# Executar interpretado
bend src/scenario5_horario.bend

# Compilar para C nativo de alto desempenho
bend src/scenario5_horario.bend -o horario_bin
./horario_bin
```
