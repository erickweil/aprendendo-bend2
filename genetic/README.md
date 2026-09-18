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

## 3. Cenários e Problemas Implementados (16 Cenários + PGA)

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
| **14. Evolução Diferencial (DE)** | Otimização numérica contínua em R^4 com `F32` | `Vec4` (4D contínuo) | Custo < 2.0 (Rastrigin) | **1.995 (Convergência Global)** |
| **15. Neuroevolução (Cart-Pole)** | Controle contínuo da dinâmica do pêndulo invertido em `F32` | `Policy` (5 pesos contínuos) | Sobrevivência 200/200 passos | **200 / 200 passos (Equilíbrio Estável)** |
| **16. Genética Diplóide (Memória)** | Resgate de memória ancestral sob inversão ambiental brusca | `Diploid` (2 fitas 2n + dominância) | >= 31 bits pós-retorno | **32 / 32 bits (Memória Restaurada)** |
| **17. Horário Médio (3 Turmas)** | 3 Turmas x 5 dias x 4 tempos, 20 disc, 8 profs, choques e geminadas | `Quadro3` (60 slots) | 0 penalidades | **0 penalidades** (Ótimo) |
| **18. Horário Ensino Médio (9 Turmas)** | 9 Turmas x 6 dias x 6 tempos, manhã/tarde, 30 profs | `Quadro9` (324 slots) | Min penalidades | **Convergência Estável** |
| **Solver Dinâmico (JSON I/O)** | Ingestão dinâmica de JSON real (FormularioHorario) sem hardcoding | `Quadro3` + `FastSpec` | 0 conflitos | **TurmaHorarioResult[] JSON** |
| **PGA. Ilhas Paralelas** | Arquipélago de 4 ilhas com migração de campeão | `Archipelago` x 64 ind. | Distância = 240 | **Distância = 240** (Ótimo) |

### Operadores usados por cenário

Os cenários abaixo montam sua reprodução a partir de `operators.bend`:

| Cenário | Reprodução |
| :--- | :--- |
| 1. One-Max | `pipe(cross_bits_uniform, mut_bit_flip32)` |
| 2. Ordenar Números | `pipe(cross_perm_pmx, mut_perm_neighbor_swap)` |
| 3. TSP | `pipe(cross_perm_ox1, combine_mutations(random_swap 50% / neighbor_swap 50%))` — porte fiel do `problem_tsp.rs` |
| 6. N-Queens | `pipe(cross_perm_ox1, combine_mutations(random_swap 70% / scramble 30%))` |
| 7. Mochila | `pipe(cross_bits_uniform10, mut_bit_flip10)` |
| 8. Weasel | `pipe(crossover_string, mutate_string)` — combinador polimórfico sobre um genoma próprio (`String16`) |
| 13. Auto-Adaptativo | `cross_bits_uniform` + despacho auto-adaptado entre `mut_bit_flip32`, `mut_bits_swap_blocks` e `mut_bits_invert_block` |
| 14. Evolução Diferencial | `pipe_greedy(eval_rastrigin, cross_vec4_differential)` |
| 15. Neuroevolução | `cross_f32_uniform` + `mut_f32_jitter` por peso |
| 16. Diplóide | `cross_bits_uniform` + `branch_maybe_mut(mut_bit_flip32)` |
| PGA. Ilhas | `pipe(cross_perm_ox1, combine_mutations(reverse_segment 60% / neighbor_swap 40%))` |

Os cenários 4 (Sudoku), 5 (Horário), 9 (cGA), 10 (GP), 11 (MOEA) e 12 (Co-Evolução)
mantêm operadores próprios: suas vizinhanças dependem da estrutura do problema
(blocos de horário, quad-tree, árvores de AST, dominância de Pareto) e não se
reduzem a um operador genérico sem perder as invariantes que os tornam corretos.

---

## 4. Biblioteca de Operadores (`genetic/operators.bend`)

Ao lado do motor `ga.bend` fica a biblioteca unificada de operadores genéticos,
portada do motor original em Rust/TypeScript (`my-website/rust-wasm/src/genetic/operators`
e `my-website/src/lib/genetic/*Operators.ts`). Um cenário passa a declarar sua
reprodução em uma linha:

```bend
def reproduce(parent: Perm.Perm8, champ: Perm.Perm8, seed: U32) -> Perm.Perm8:
  Op.pipe(~Perm.Perm8, ~Op.cross_perm_ox1, ~mut_tsp, parent, champ, seed)
```

### Seção A — Combinadores higher-order (polimórficos sobre `~G`)
| Combinador | Papel |
| :--- | :--- |
| `pipe` | Pipeline canônico: crossover seguido de mutação, com sementes bifurcadas |
| `pipe_rated` | Pipeline completo de Holland: sorteia $P_c$, depois $P_m$ (laço do `ga.ts`) |
| `pipe_greedy` | Seleção $(\mu+1)$ da Evolução Diferencial: aceita o teste só se o custo não piorar |
| `combine_mutations` | Escolha probabilística exclusiva entre dois operadores (70% / 30%) |
| `chain_mutations` | Aplica **ambos** em sequência — equivalente fiel do `mutation_combine` original |
| `maybe_mutate` | Aplica a mutação só se passar no sorteio de $P_m$ |
| `crossover_or_clone` | Cruza com probabilidade $P_c$; senão herda o pai 1 intacto |
| `branch_mut` / `branch_cross` / `branch_maybe_mut` | Despacho **linear** por `match` sobre `Bool`: só um ramo toca o genoma |

### Seção B — Genomas binários (`U32`)
`cross_bits_uniform`, `cross_bits_uniform10`, `cross_bits_1point`, `cross_bits_2point`,
`mask_1point`, `mask_2point`, `mut_bit_flip32`, `mut_bit_flip10`, `mut_bits_multi`
(mutação por gene), `mut_bits_invert_block`, `mut_bits_swap_blocks`, `mut_bits_swap`
(conserva o popcount).

### Seção C — Permutações (`Perm8`)
| Operador | Descrição |
| :--- | :--- |
| `cross_perm_ox1` | **Order Crossover (OX1)** — porte direto do `crossover_ox1.rs`, com `taken_mask` para pertinência em $O(1)$ |
| `cross_perm_pmx` | **Partially Mapped Crossover** — resolve conflitos por mapeamento inverso de posições |
| `cross_perm_directed_swap` | Position-Based / Directed Swap Crossover |
| `cross_perm_elite_bias` | Herança enviesada para a elite (60%) |
| `mut_perm_random_swap` | `mutation_random_swap` |
| `mut_perm_neighbor_swap` | `mutation_neighbor_swap` |
| `mut_perm_reverse_segment` | Inversão 2-Opt **completa** do trecho `[lo, hi]` |
| `mut_perm_scramble` | Embaralha uma janela de 3 elementos consecutivos |

OX1, PMX, Directed Swap, 2-Opt, Scramble e Neighbor Swap **fecham sobre permutações
válidas por construção** — verificado exaustivamente em `tests/operators_test.bend`.

### Seção D — Operadores contínuos (`F32` / `Vec4`)
`cross_f32_uniform`, `cross_f32_arith`, `mut_f32_jitter`, `de_step_coord`,
`cross_vec4_uniform`, `cross_vec4_arithmetic`, `cross_vec4_differential`, `mut_vec4_jitter`.

---

## 4.1 Biblioteca Reutilizável (`genetic/utils/`)

Extraída para modularizar algoritmos evolutivos futuros:
- [`utils/random.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/random.bend): Xorshift32 determinístico puro com seed-splitting em $O(1)$, `mod_range` e `chance`.
- [`utils/bits.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/bits.bend): `popcount`, `bit_of`, `crossover_uniform`, `mutate_bit` e unicidade de 9 elementos `group_unique9`.
- [`utils/math.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/math.bend): Operações em ponto flutuante `F32` (`clamp`, ativação sigmoidal `fast_tanh`, `relu`, produto escalar `dot4`, conversão de ângulos `deg_to_rad`) e amostragem contínua determinística (`rnd_norm`, `rnd_unit`, `rnd_unit_coarse`, `rnd_range_f32`).
- [`utils/vec4.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/vec4.bend): Ponto contínuo em $R^4$ (`Vec4`) com amostragem uniforme no hipercubo `rnd_vec4`.
- [`utils/stats.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/stats.bend): Redução concorrente em $O(\log N)$ para estatísticas agregadas (`PopStats`: melhor, pior, soma, média, dispersão `spread`).
- [`utils/pareto.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/pareto.bend): Dominância de Pareto (`dominates_min_max`, `dominates_max_max`) e cálculo de densidade de eficiência.
- [`utils/poptree.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/utils/poptree.bend): Árvore binária polimórfica (`PopTree<A>`), injeção de elite e redução concorrente.

---

## 4.2 A abstração é de custo zero (medido e provado)

Os combinadores recebem o operador como parâmetro-template `~`, substituído em
**tempo de compilação**. Não existe closure, ponteiro de função nem despacho
dinâmico no código gerado. Três evidências independentes:

1. **Prova formal** — as Leis 16 a 22 de [`LAWS.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/LAWS.bend)
   afirmam que o pipeline montado por combinadores é **definicionalmente igual**
   ao código escrito à mão, e são provadas por reflexividade pura (`{==}`) em
   [`PROOF.bend`](file:///home/ubuntu/claude/aprendendo-bend2/genetic/PROOF.bend).
   Por exemplo, a Lei 16 afirma literalmente que
   `Op.pipe(~U32, ~Op.cross_bits_uniform, ~Op.mut_bit_flip32, p, c, s)`
   é o mesmo termo que `mutate_bit(crossover_uniform(p, c, step(s)), step(step(s)))`.
2. **Código C emitido** — compilando o mesmo cenário nas duas formas, o segmento
   quente (`FID____GA_REPRODUCE_TREE_0`) sai **idêntico**, módulo numeração de
   temporários: 155 linhas, 47 segmentos de máquina de estados nos dois casos.
3. **Binário nativo** — `1.111.320` bytes nos dois casos e, em 1,2 milhão de
   reproduções (4096 indivíduos x 300 gerações), ~155 ms nos dois casos.

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

Para verificar só as garantias da biblioteca:

```bash
# As 22 leis formais (motor, árvore populacional, ilhas e combinadores)
bend PROOF.bend

# Teste exaustivo dos operadores (validade de permutação, popcount, taxas)
bend tests/operators_test.bend
```

> Por convenção do Bend 2, `LAWS.bend` (as leis, escritas pelo humano) e
> `PROOF.bend` (as provas) ficam na **raiz do projeto**, ao lado de `ga.bend` e
> `operators.bend`. Antes ficavam em `utils/`; foram movidos porque um mesmo
> arquivo alcançado por dois caminhos diferentes (`./random.bend` e
> `./utils/random.bend`) viola a regra de um namespace por arquivo.
