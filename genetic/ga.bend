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

# Profundidade de bifurcação DENTRO de cada ilha. O padrão é 0: a evolução
# local é inteiramente sequencial, e o paralelismo vem só do arquipélago.
#
# Isso é contra-intuitivo, porque o escalonador do Bend precisa de MUITAS
# tarefas para preencher os cores — medido com trabalho puro e balanceado em
# 4 cores, 4 tarefas dão 1,90x e 64 tarefas dão 2,92x. Mas naquele teste as
# tarefas eram criadas UMA vez e viviam o programa inteiro. Aqui uma geração
# é um fork-join completo: com fork_d = 3, 5.000 gerações x 8 ilhas viram
# 320.000 episódios de bifurcação, cada um distribuindo microssegundos de
# trabalho. Medido, fork_d = 3 custa de 2x a 3x:
#
#     bench_perm  4T: 268ms (sequencial)  ->  855ms (fork_d = 3)
#     bench_bits  4T: 199ms (sequencial)  -> 1008ms (fork_d = 3)
#
# Ou seja: o que escala não é subdividir a geração, é ter mais ilhas — cada
# ilha é uma tarefa longeva que roda milhares de gerações sem sincronizar.
# O parâmetro continua exposto em `run_generations_at` para populações
# gigantes com aptidão cara, onde a subdivisão pode compensar.
# Ver PERFORMANCE.md §3.
def default_fork_depth() -> Nat:
  0n

# Reproduz uma árvore populacional aplicando a closure de reprodução.
# `fork_d` é a granularidade: os `fork_d` níveis do topo bifurcam em paralelo
# e todo o resto da subárvore roda sequencialmente, aproveitando a cache local
# do core. Como a computação é pura e as sementes já são bifurcadas de forma
# determinística, `fork_d` altera SÓ o escalonamento — o resultado é idêntico.
def reproduce_tree(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                   tree: T.PopTree<Ind<G>>, fork_d: Nat,
                   +seed: U32, +champ: Ind<G>) -> T.PopTree<Ind<G>>:
  match tree fork_d:
    case T.Leaf{ind} _:
      +champ = champ
      +parent_g = Ind.gene(G, ind)
      +champ_g = Ind.gene(G, champ)
      +child_g = repro(parent_g, champ_g, seed)
      +child_f = fit(child_g)
      T.Leaf{Ind{child_g, child_f}}
    case T.Node{left, right} 0n:
      # abaixo do corte: sequencial, sem criar descritores de tarefa
      +seed = seed; +champ = champ
      +l = reproduce_tree(~G, ~repro, ~fit, left, 0n, R.split.fst(seed), champ)
      +r = reproduce_tree(~G, ~repro, ~fit, right, 0n, R.split.snd(seed), champ)
      T.Node{l, r}
    case T.Node{left, right} 1n+k:
      # acima do corte: bifurcação paralela
      +seed = seed; +champ = champ; +k = k
      l r = reproduce_tree(~G, ~repro, ~fit, left, k, R.split.fst(seed), champ) reproduce_tree(~G, ~repro, ~fit, right, k, R.split.snd(seed), champ)
      T.Node{l, r}

# Um passo geracional completo com injeção de elitismo
def step_generation(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                    +tree: T.PopTree<Ind<G>>, fork_d: Nat, +seed: U32) -> T.PopTree<Ind<G>>:
  +champ = best_ind(G, tree)
  +next_pop = reproduce_tree(~G, ~repro, ~fit, tree, fork_d, seed, champ)
  T.inject_elite(Ind<G>, next_pop, champ)

# Executa g gerações na ilha local com granularidade de bifurcação explícita
def run_generations_at(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                       g: Nat, fork_d: Nat, tree: T.PopTree<Ind<G>>,
                       +seed: U32) -> T.PopTree<Ind<G>>:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = R.step(seed)
      +fork_d = fork_d
      +next_tree = step_generation(~G, ~repro, ~fit, tree, fork_d, seed)
      run_generations_at(~G, ~repro, ~fit, p, fork_d, next_tree, next_seed)

# Executa g gerações evolutivas na ilha local com a granularidade padrão
def run_generations(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                    g: Nat, tree: T.PopTree<Ind<G>>, +seed: U32) -> T.PopTree<Ind<G>>:
  run_generations_at(~G, ~repro, ~fit, g, default_fork_depth(), tree, seed)

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

# Campeão global absoluto somando todas as ilhas do arquipélago.
# A redução bifurca no nível do arquipélago (uma tarefa por sub-arquipélago,
# criada uma vez por época), nunca dentro da ilha: subdividir a redução local
# criaria tarefas microscópicas a cada geração. Junto com `migrate_champion`,
# esta era a fração serial de cada época — com 64 ilhas x 64 indivíduos são
# 4.096 nós percorridos duas vezes por época.
def best_archipelago(-G: Data, +arch: ArchTree<G>) -> Ind<G>:
  match arch:
    case SingleIsland{tree}:
      best_ind(G, tree)
    case ArchBranch{left, right}:
      bl br = best_archipelago(G, left) best_archipelago(G, right)
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
      l r = migrate_champion(G, left, champ) migrate_champion(G, right, champ)
      ArchBranch{l, r}

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
