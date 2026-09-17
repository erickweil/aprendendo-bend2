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

## 3. Cenários e Problemas Implementados

| Cenário | Descrição | Representação | Métrica Ótima | Resultado Obtido |
| :--- | :--- | :--- | :--- | :--- |
| **1. Bit Maxing (One-Max)** | Maximizar bits 1 em palavra de 32 bits | `U32` (32 genes binários) | 32 / 32 bits | **32 / 32 bits** (Ótimo) |
| **2. Ordenar Números** | Ordenar permutação de 8 números | `Perm8` (8 campos) | 28 / 28 pares | **[0, 1, 2, 3, 4, 5, 6, 7]** (Ótimo) |
| **3. Caixeiro Viajante (TSP)** | Rota fechada entre 8 cidades 2D | `Perm8` (ciclo fechado) | Distância = 240 | **Distância = 240** (Ótimo) |
| **4. Sudoku Solver** | Resolver grade 4x4 com pistas | `Board4` (16 células) | 0 conflitos | **0 conflitos** (Ótimo) |
| **5. Solver de Horário** | Grade de 2 turmas x 8 tempos, 3 profs, choques, indisponibilidade e blocos | `Timetable` (`Schedule8` x 2) | 0 penalidades | **0 penalidades** (Ótimo) |
| **6. 8-Rainhas (N-Queens)** | Dispor 8 rainhas sem ataques mútuos | `Perm8` (8 colunas) | 0 ataques diagonais | **0 ataques diagonais** (Ótimo) |
| **7. Problema da Mochila (Knapsack)** | 10 itens com pesos e valores, capacidade = 80kg | `U32` (bitmask 10 bits) | Valor >= 175, Peso <= 80 | **Valor = 175, Peso = 79** (Ótimo) |
| **8. Evolução de Strings (Weasel)** | Evolução da frase `"BEND IS PARALLEL"` | `String16` (16 caracteres) | 16 / 16 caracteres | **"BEND IS PARALLEL"** (Ótimo) |
| **PGA. Ilhas Paralelas** | Arquipélago de 4 ilhas com migração do campeão | `Archipelago` x 64 indivíduos | Distância = 240 | **Distância = 240** (Ótimo) |

---

## 4. Resultados e Tempos de Execução

Testado na VM (4 vCPUs AMD EPYC, Linux x86_64, Bend 2.0.5, Clang 19.1.1):

| Cenário | População | Gerações | Tempo Interpretado (`bend`) | Tempo Compilado C (`-o`) | Solução Ótima? |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **1. Bit Maxing (One-Max)** | 32 indivíduos | 25 | 0.357s | **0.016s** | **Sim (True)** |
| **2. Ordenar Números** | 32 indivíduos | 40 | 0.452s | **0.020s** | **Sim (True)** |
| **3. Caixeiro Viajante (TSP)** | 32 indivíduos | 50 | 0.521s | **0.037s** | **Sim (True)** |
| **4. Sudoku Solver** | 32 indivíduos | 35 | 0.735s | **0.023s** | **Sim (True)** |
| **5. Solver de Horário Escolar** | 32 indivíduos | 80 | 1.045s | **0.034s** | **Sim (True)** |
| **6. 8-Rainhas (N-Queens)** | 64 indivíduos | 60 | 0.890s | **0.028s** | **Sim (True)** |
| **7. Problema da Mochila** | 32 indivíduos | 35 | 0.312s | **0.015s** | **Sim (True)** |
| **8. Evolução de Strings** | 64 indivíduos | 75 | 1.250s | **0.042s** | **Sim (True)** |
| **PGA. Modelo de Ilhas** | 4 ilhas x 16 (64 total) | 5 épocas x 10 | 0.950s | **0.031s** | **Sim (True)** |

Todos os 9 programas compilados em C executam em **menos de 45 milissegundos**!

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
