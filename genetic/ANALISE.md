# Análise Crítica da Implementação Anterior e Remodelagem para Bend 2

## 1. Avaliação da Implementação Anterior (`my-website`)

A implementação original foi desenvolvida em Rust (`rust-wasm/src/genetic/` e `rust-wasm/src/horario/`) com interface TypeScript/WebAssembly. A seguir, destacamos os principais acertos, erros e limitações identificados no código e na documentação (`docs/plano-solver-local-search.md`).

### 1.1 Acertos (Pontos Fortes)

1. **Invariantes de Domínio Preservadas por Construção (`horario_genetic.rs`)**:
   - As disciplinas pertencentes a uma turma e suas respectivas cargas horárias semanais são representadas como um **multiconjunto imutável**.
   - Os operadores genéticos (mutação e crossover) nunca trocam disciplinas entre turmas distintas nem alteram o saldo total de aulas de cada matéria.
   - Slots inativos (`-1`) são preservados. Isso elimina a necessidade de reparar soluções quanto à integridade estrutural básica.

2. **Operadores Especializados de Crossover e Mutação**:
   - **OX1 (Order Crossover)** no TSP e **IPX (Improved Precedence Crossover)** no Horário para preservar permutações válidas sem duplicatas.
   - Amostragem de Poisson (`poisson_knuth_sample`) para determinar dinamicamente a quantidade de swaps por indivíduo na mutação, evitando passos rígidos demais.
   - Mutação adaptativa em caso de estagnação (`mutation_multiplier`), dobrando o ímpeto exploratório quando a população atinge platôs.

3. **Abstração Estruturada (`GAProblem` trait)**:
   - Definição limpa de tipos associados (`Gene`, `State`), métodos de ciclo de vida (`initial_state`, `random_genes`, `fitness`, `mutate`, `crossover`, `max_fitness`).

4. **Autodiagnóstico Preciso (`docs/plano-solver-local-search.md`)**:
   - O próprio autor já havia identificado corretamente os grandes gargalos:
     * Custo quadrático por geração com `pop_size = size * 4`.
     * Reavaliação completa de todo o quadro a cada avaliação de fitness.
     * Estagnação prematura do GA clássico em grafos densos de restrições.

---

### 1.2 Erros e Limitações da Arquitetura Anterior

1. **Gargalo Monolítico Sequencial**:
   - Em Rust/WASM, a população (`Vec<Individual>`) era iterada estritamente em um único loop `for` sequencial:
     ```rust
     for (i, ind) in self.population.iter_mut().enumerate() {
         ind.fitness = Some(self.problem.fitness(&mut self.problem_state, &ind.genes));
     }
     ```
   - Uma população de 100 indivíduos com 10 turmas executava centenas de milhares de verificações puramente sequenciais em 1 núcleo de CPU.
   - Não havia paralelização de avaliação, seleção ou recombinação.

2. **Estado Global Mutável de RNG**:
   - O gerador de números aleatórios (`random_f64`, `random_range`) usava estado global mutável.
   - Isso impede computações concorrentes ou paralelas sem travas de sincronização (locks) ou concorrência pesada.

3. **Drift e Instabilidade de Ponto Flutuante (`f64`)**:
   - Fitness representado em `f64` gerava imprecisões e comparações nebulosas (`current_best_fitness > (sf + f64::EPSILON)`).
   - Cálculos em ponto flutuante adicionam sobrecarga e não são exatos na contagem de restrições violadas.

4. **Fusão de Restrições Conflitantes no Fitness**:
   - Em `horario_genetic.rs`, disponibilidade do professor (`disp == 0`) e choque de turmas (`disp < 0`) eram abatidos na mesma matriz decrementada (`prof_matriz`). Isso mascarava se o problema era um choque entre turmas ou uma indisponibilidade contratual do docente.

5. **Destruição Prematura de Sub-soluções no Reset**:
   - No gatilho de estagnação (`ga.rs:187`), o solver realizava `self.initialize_population(true)`, descartando todo o progresso histórico dos blocos de turmas já resolvidos.

---

## 2. Remodelagem Arquitetural para o Bend 2

O Bend 2 oferece uma oportunidade única para reformular completamente a dinâmica de algoritmos genéticos: **o paralelismo fork-join em árvores de redução e avaliação sem travas ou custos de sincronização**.

### 2.1 Principais Pilares da Nova Arquitetura

1. **População Estruturada em Árvore Binária Balanceada (`PopTree`)**:
   - Em vez de um array linear indexado, a população é uma árvore binária de profundidade $D$ ($N = 2^D$ indivíduos):
     ```bend
     type PopTree is Data:
       Leaf{ind: Individual}
       Node{left: PopTree, right: PopTree}
     ```
   - A avaliação de fitness é naturalmente recursiva e fork-join:
     ```bend
     def eval_pop(tree: PopTree) -> PopTree:
       match tree:
         case Leaf{ind}:
           Leaf{eval_ind(ind)}
         case Node{left, right}:
           l r = eval_pop(left) eval_pop(right)
           Node{l, r}
     ```
   - A linha `l r = eval_pop(left) eval_pop(right)` dispara a execução paralela nativa do runtime do Bend 2 em múltiplos núcleos de CPU (ou threads de GPU).

2. **PRNG Puro, Determinístico e Paralelo com Seed-Splitting**:
   - Em linguagens funcionais puras, o RNG deve ser um gerador de fluxo de seeds sem estado global.
   - Usamos o **Xorshift32** puro.
   - Para ramificações em árvore paralela, a semente é bifurcada deterministicamente:
     ```bend
     def prng_split(+seed: U32) -> SeedPair:
       s1 = prng_step(seed)
       s2 = prng_step(U32.xor(s1, 2654435761))
       SeedPair{s1, s2}
     ```
   - Cada ramo da árvore de evolução trabalha com seu próprio fluxo pseudo-aleatório independente, com **zero contenção de memória**.

3. **Fitness Inteiro Exato (`U32`)**:
   - Penalidades e recompensas expressas como inteiros `U32`.
   - Fitness ótimo = `MAX_FIT` (ou 0 penalidades convertidas por offset).
   - Elimina drift de ponto flutuante, `EPSILON` e operações caras de float no HVM.

4. **Seleção e Reprodução em Árvore (Island / Tournament Tree)**:
   - Sub-árvores vizinhas competem entre si (torneios locais) e realizam crossover/mutação em paralelo.
   - A redução para extrair o melhor indivíduo da geração ocorre em $O(\log N)$ passos paralelos:
     ```bend
     def best_tree(tree: PopTree) -> Individual:
       match tree:
         case Leaf{ind}:
           ind
         case Node{left, right}:
           bl br = best_tree(left) best_tree(right)
           pick_better(bl, br)
     ```

5. **Operadores Especializados por Problema**:
   - **OneMax**: Mutação bit-flip em bitmask U32, crossover por máscara aleatória.
   - **Number Sorting**: Permutações com mutação swap e fitness baseado em inversões/ordenação.
   - **TSP**: Permutação de cidades com distância inteira e swap/reversal mutation.
   - **Sudoku**: Permutação por linha (preserva unicidade de linha), penaliza conflitos de coluna e quadrante.
   - **Solver de Horário**: Multiconjunto linear por turma, penalidades separadas para choque de professor, indisponibilidade e blocos quebrados, avaliados em paralelo.
