# Bend 2 - Solver Genético Paralelo em Árvore & Modelo de Ilhas (PGA)

Implementação completa e de alto desempenho de um motor de **Algoritmo Genético Paralelo** na linguagem **Bend 2 (2.0.5)**, remodelando e aprimorando a arquitetura original desenvolvida em Rust/TypeScript (`my-website/rust-wasm/src/genetic` e `horario`).

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
2. **Modelo de Ilhas Paralelas (Parallel Island Model - PGA)**:
   - Um arquipélago de $2^K$ ilhas (`Archipelago`), onde cada ilha executa em um thread/processador isolado com seu próprio fluxo evolutivo.
   - A cada época (epoch), o campeão global migra para todas as ilhas, combinando diversidade genética e recombinação de alta performance.
3. **PRNG Determinístico Puro com Seed-Splitting**:
   - Baseado em **Xorshift32** puro, sem variáveis globais.
   - Para ramificações na árvore, a semente é bifurcada em $O(1)$:
     ```bend
     l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
     ```
   - Zero locks, zero contenção de memória, 100% determinístico e thread-safe.
4. **Fitness Exato em Inteiros (`U32`)**:
   - Zero tolerância/epsilon drift, execução direta no compilador C e GPU.
5. **Vizinhanças Inspiradas no Plano de Busca Local**:
   - `SwapSlot`: Ajuste fino intra-turma.
   - `SwapBloco`: Preserva agrupamento de aulas geminadas.
   - `SwapColuna`: Troca períodos em todas as turmas simultaneamente, preservando ausência de choques de professores.
   - `SwapBlocoColuna`: Reorganiza blocos inteiros sem quebrar agrupamento nem criar novos choques.

---

## 3. Cenários e Problemas Implementados (15 Cenários)

| Cenário | Descrição | Representação | Métrica Ótima | Resultado Obtido |
| :--- | :--- | :--- | :--- | :--- |
| **1. One-Max** | Maximizar bits 1 em palavra de 32 bits | `U32` (32 genes binários) | 32 / 32 bits | **32 / 32 bits** (Ótimo) |
| **2. Ordenar Números** | Ordenar permutação de 8 números | `Perm8` (8 campos) | 28 / 28 pares | **[0, 1, 2, 3, 4, 5, 6, 7]** (Ótimo) |
| **3. Caixeiro Viajante (TSP)** | Rota fechada entre 8 cidades 2D | `Perm8` (ciclo fechado) | Distância = 240 | **Distância = 240** (Ótimo) |
| **4. Sudoku 9x9 (Quadro Vazio)** | Gerar e resolver grade 9x9 do zero (81 zeros) | `Sudoku9` (9 x `Row9`) | 162 / 162 (0 conflitos) | **162 / 162** (0 conflitos) |
| **5. Solver de Horário** | Grade 2 turmas x 8 tempos, 3 profs, choques e blocos | `Timetable` (`Schedule8` x 2) | 0 penalidades | **0 penalidades** (Ótimo) |
| **6. 8-Rainhas (N-Queens)** | Dispor 8 rainhas sem ataques mútuos | `Perm8` (8 colunas) | 0 ataques diagonais | **0 ataques diagonais** (Ótimo) |
| **7. Mochila 0/1 (Knapsack)** | 10 itens com pesos e valores, capacidade = 80kg | `U32` (bitmask 10 bits) | Valor >= 175, Peso <= 80 | **Valor = 175, Peso = 79** (Ótimo) |
| **8. Evolução de Strings (Weasel)** | Evolução da frase `"BEND IS PARALLEL"` | `String16` (16 caracteres) | 16 / 16 caracteres | **"BEND IS PARALLEL"** (Ótimo) |
| **9. Cellular GA (cGA)** | Grade 2D 8x8 em Quad-Tree superando Deceptive Trap | `QuadTree` (64 células) | 32 / 32 bits | **32 / 32 bits** (Ótimo Global) |
| **10. Programação Genética (GP)** | Regressão simbólica de ASTs com controle de bloat | `Expr` (AST algébrico) | Erro = 0 | **`(1 + (x * x))` (Erro = 0)** |
| **11. Otimização Multi-Objetivo** | Max(Valor) e Min(Peso) via Dominância de Pareto | `MOInd` (Val, Wt, Gene) | Fronteira de Pareto | **3 Especialistas Trade-Off** |
| **12. Co-Evolução Competitiva** | Host vs Parasita descobrindo Redes de Ordenação | `Net` (6 CAS) vs `Arr4` | Lema 0-1 (16/16) | **`[5 3 2 4 1 0]` (16/16 provado)** |
| **13. Motor Auto-Adaptativo** | Taxa de mutação e operadores no próprio genoma | `SAInd` (Taxa, Op, Gene) | 1064 / 1064 pts | **1064 / 1064 (Royal Road 4/4)** |
| **14. Evolução Diferencial (DE)** | Otimização numérica contínua em R^4 com `F32` | `Vec4` (4D contínuo) | Custo < 2.0 (Rastrigin) | **1.172 (Convergência Global)** |
| **PGA. Ilhas Paralelas** | Arquipélago de 4 ilhas com migração de campeão | `Archipelago` x 64 ind. | Distância = 240 | **Distância = 240** (Ótimo) |

---

## 4. Biblioteca Reutilizável (`genetic/utils/`)

Extraída para modularizar algoritmos evolutivos futuros:
- [`utils/random.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/random.bend): Xorshift32 determinístico puro com seed-splitting em $O(1)$, `mod_range` e `chance`.
- [`utils/bits.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/bits.bend): `popcount`, `bit_of`, `crossover_uniform`, `mutate_bit` e unicidade de 9 elementos `group_unique9`.
- [`utils/pareto.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/pareto.bend): Dominância de Pareto (`dominates_min_max`, `dominates_max_max`) e cálculo de densidade de eficiência.
- [`utils/poptree.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/poptree.bend): Árvore binária polimórfica (`PopTree<A>`), injeção de elite e redução concorrente.

---

## 5. Como Executar

Para rodar toda a suite automatizada:

```bash
cd ~/claude/aprendendo-bend2/genetic
./run_all.sh
```

Para executar ou compilar um cenário individual:

```bash
# Executar interpretado
bend src/scenario14_differential_evolution.bend

# Compilar para binário nativo C de alto desempenho
bend src/scenario14_differential_evolution.bend -o de_bin
./de_bin
```
