import Base
import ./utils/random.bend as R
import ./utils/poptree.bend as T
import ./utils/stats.bend as S

# ================================================================
# BEND 2 GENERIC GENETIC ALGORITHM ENGINE (ga.bend)
# ================================================================
# Motor Genético Polimórfico e Paralelo de Alta Performance.
# Totalmente agnóstico do genoma G (representação opaca).
# Suporta:
# 1. População em Árvore Binária Fork-Join (PopTree<Ind<G>>)
# 2. Estatísticas Agregadas em O(log N) (PopStats)
# 3. Elitismo Estrito com Preservação de Dimensão
# 4. Modelo de Arquipélago Paralelo (ArchTree<G>) com Migração Inter-Ilhas
# ================================================================

# Indivíduo genérico com genoma G e pontuação de aptidão (fitness)
type Ind<-G: Data> is Data:
  Ind{gene: G, fit: U32}

def make_ind(-G: Data, +gene: G, +fit: U32) -> Ind<G>:
  Ind{gene, fit}

def Ind.gene(-G: Data, ind: Ind<G>) -> G:
  Ind{g, _} = ind
  g

def Ind.fit(-G: Data, ind: Ind<G>) -> U32:
  Ind{_, f} = ind
  f

def pick_better(-G: Data, +a: Ind<G>, +b: Ind<G>) -> Ind<G>:
  Bool.pick(Ind<G>, U32.is_ge(Ind.fit(G, a), Ind.fit(G, b)), a, b)

# ----------------------------------------------------------------
# GERAÇÃO E REDUÇÃO EM ÁRVORE BINÁRIA
# ----------------------------------------------------------------

# Inicializa uma população de profundidade d (2^d indivíduos)
def gen_population(~G: Type, ~init: U32 -> G, ~fit: G -> U32,
                   d: Nat, +seed: U32) -> T.PopTree<Ind<G>>:
  match d:
    case 0n:
      +g = init(seed)
      +f = fit(g)
      T.Leaf{Ind{g, f}}
    case 1n+p:
      +p = p; +seed = seed
      l r = gen_population(~G, ~init, ~fit, p, R.split.fst(seed)) gen_population(~G, ~init, ~fit, p, R.split.snd(seed))
      T.Node{l, r}

# Extração paralela do melhor indivíduo (campeão da população)
def best_ind(-G: Data, +tree: T.PopTree<Ind<G>>) -> Ind<G>:
  match tree:
    case T.Leaf{ind}:
      ind
    case T.Node{left, right}:
      +bl = best_ind(G, left)
      +br = best_ind(G, right)
      pick_better(G, bl, br)

# Cálculo de estatísticas agregadas (melhor, pior, soma, média, N)
def population_stats(-G: Data, +tree: T.PopTree<Ind<G>>) -> S.PopStats:
  match tree:
    case T.Leaf{ind}:
      S.leaf_stats(Ind.fit(G, ind))
    case T.Node{left, right}:
      +sl = population_stats(G, left)
      +sr = population_stats(G, right)
      S.merge_stats(sl, sr)

# Re-avalia toda a população com uma nova função de fitness (ex: mudança ambiental)
def reevaluate_pop(~G: Type, ~fit: G -> U32, tree: T.PopTree<Ind<G>>) -> T.PopTree<Ind<G>>:
  match tree:
    case T.Leaf{ind}:
      +g = Ind.gene(G, ind)
      +f = fit(g)
      T.Leaf{Ind{g, f}}
    case T.Node{left, right}:
      +l = reevaluate_pop(~G, ~fit, left)
      +r = reevaluate_pop(~G, ~fit, right)
      T.Node{l, r}

# ----------------------------------------------------------------
# OPERADORES GENÉTICOS E EVOLUÇÃO (ÁRVORE LOCAL)
# ----------------------------------------------------------------

# Reproduz uma árvore populacional aplicando a closure de reprodução
def reproduce_tree(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                   tree: T.PopTree<Ind<G>>, +seed: U32, +champ: Ind<G>) -> T.PopTree<Ind<G>>:
  match tree:
    case T.Leaf{ind}:
      +champ = champ
      +parent_g = Ind.gene(G, ind)
      +champ_g = Ind.gene(G, champ)
      +child_g = repro(parent_g, champ_g, seed)
      +child_f = fit(child_g)
      T.Leaf{Ind{child_g, child_f}}
    case T.Node{left, right}:
      +seed = seed; +champ = champ
      +l = reproduce_tree(~G, ~repro, ~fit, left, R.split.fst(seed), champ)
      +r = reproduce_tree(~G, ~repro, ~fit, right, R.split.snd(seed), champ)
      T.Node{l, r}

# Um passo geracional completo com injeção de elitismo
def step_generation(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                    +tree: T.PopTree<Ind<G>>, +seed: U32) -> T.PopTree<Ind<G>>:
  +champ = best_ind(G, tree)
  +next_pop = reproduce_tree(~G, ~repro, ~fit, tree, seed, champ)
  T.inject_elite(Ind<G>, next_pop, champ)

# Executa g gerações evolutivas sequencialmente na ilha local
def run_generations(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                    g: Nat, tree: T.PopTree<Ind<G>>, +seed: U32) -> T.PopTree<Ind<G>>:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = R.step(seed)
      +next_tree = step_generation(~G, ~repro, ~fit, tree, seed)
      run_generations(~G, ~repro, ~fit, p, next_tree, next_seed)

# ----------------------------------------------------------------
# MODELO DE ARQUIPÉLAGO MULTI-ILHAS (PGA COARSE-GRAINED)
# ----------------------------------------------------------------

type ArchTree<-G: Data> is Data:
  SingleIsland{tree: T.PopTree<Ind<G>>}
  ArchBranch{left: ArchTree<G>, right: ArchTree<G>}

# Gera um arquipélago com 2^d ilhas independentes, cada uma com 2^pop_d indivíduos
def gen_archipelago(~G: Type, ~init: U32 -> G, ~fit: G -> U32,
                    d: Nat, +seed: U32, pop_d: Nat) -> ArchTree<G>:
  match d:
    case 0n:
      SingleIsland{gen_population(~G, ~init, ~fit, pop_d, seed)}
    case 1n+p:
      +p = p; +seed = seed; +pop_d = pop_d
      l r = gen_archipelago(~G, ~init, ~fit, p, R.split.fst(seed), pop_d) gen_archipelago(~G, ~init, ~fit, p, R.split.snd(seed), pop_d)
      ArchBranch{l, r}

# Campeão global absoluto somando todas as ilhas do arquipélago
def best_archipelago(-G: Data, +arch: ArchTree<G>) -> Ind<G>:
  match arch:
    case SingleIsland{tree}:
      best_ind(G, tree)
    case ArchBranch{left, right}:
      +bl = best_archipelago(G, left)
      +br = best_archipelago(G, right)
      pick_better(G, bl, br)

# Evolução concorrente de todas as ilhas por uma época de e gerações
def evolve_archipelago(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                       arch: ArchTree<G>, +seed: U32, e: Nat) -> ArchTree<G>:
  match arch:
    case SingleIsland{tree}:
      SingleIsland{run_generations(~G, ~repro, ~fit, e, tree, seed)}
    case ArchBranch{left, right}:
      +seed = seed; +e = e
      l r = evolve_archipelago(~G, ~repro, ~fit, left, R.split.fst(seed), e) evolve_archipelago(~G, ~repro, ~fit, right, R.split.snd(seed), e)
      ArchBranch{l, r}

# Migração do campeão global para o slot de elite de cada ilha
def migrate_champion(-G: Data, arch: ArchTree<G>, +champ: Ind<G>) -> ArchTree<G>:
  match arch:
    case SingleIsland{tree}:
      SingleIsland{T.inject_elite(Ind<G>, tree, champ)}
    case ArchBranch{left, right}:
      +champ = champ
      ArchBranch{migrate_champion(G, left, champ), migrate_champion(G, right, champ)}

# Loop completo de arquipélago: épocas de evolução concorrente + migração periódica
def run_archipelago(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                    epochs: Nat, arch: ArchTree<G>, +seed: U32, e: Nat) -> ArchTree<G>:
  match epochs:
    case 0n:
      arch
    case 1n+p:
      +next_seed = R.step(seed); +e = e
      +evolved = evolve_archipelago(~G, ~repro, ~fit, arch, seed, e)
      +champ = best_archipelago(G, evolved)
      +migrated = migrate_champion(G, evolved, champ)
      run_archipelago(~G, ~repro, ~fit, p, migrated, next_seed, e)
