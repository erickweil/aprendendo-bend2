import Base
import ./../utils/random.bend as R
import ./utils/poptree.bend as T
import ./stats.bend as S

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

# Resultado de uma geração: a nova população e o melhor indivíduo DELA,
# carregado como aptidão e genoma soltos, não como um `Ind`.
#
# Essa separação é o ponto do design. O laço geracional antes lia a árvore
# duas vezes — `best_ind` para achar o campeão e `reproduce_tree` para gerar
# os filhos. Medido com 2,56 milhões de indivíduos: reproduzir custa 28ms e
# a busca do campeão custa 224ms, 9x mais, apesar de não alocar nada.
#
# A causa não é percorrer a árvore (percorrer todos os nós sem abrir os
# indivíduos custa 29ms), é ABRIR um registro compartilhado: `pick_better`
# fazia `Ind.fit(a)` e `Ind.fit(b)` em valores `+`, e destruir um nó
# compartilhado obriga o runtime a copiá-lo. São 126 cópias por geração.
#
# Aqui a aptidão sobe a recursão como um `U32` solto, então comparar é
# aritmética escalar e nenhum registro é aberto. O campeão é descoberto
# durante a própria construção da população, numa travessia só.
type Gen<-G: Data> is Data:
  Gen{pop: T.PopTree<Ind<G>>, bfit: U32, bgene: G}

def Gen.pop(-G: Data, g: Gen<G>) -> T.PopTree<Ind<G>>:
  Gen{p, _, _} = g
  p

# O campeão que a travessia fundida JÁ descobriu. Sem estes acessores o
# chamador precisa rodar `best_ind` de novo sobre a árvore final — a exata
# segunda leitura que o tipo `Gen` existe para eliminar.
def Gen.best(-G: Data, g: Gen<G>) -> Ind<G>:
  Gen{_, bf, bg} = g
  Ind{bg, bf}

def Gen.bfit(-G: Data, g: Gen<G>) -> U32:
  Gen{_, bf, _} = g
  bf

# Seleção do campeão entre os dois lados. Os seletores devolvem SÓ a aptidão e
# o genoma: a população fica fora do ramo condicional, no topo de `merge_gen`.
# Assim `Gen.pop` projeta a árvore sem depender da comparação. Isso mantém a
# fusão barata em runtime e é o que torna a Lei 21 (LAWS.bend) demonstrável:
# o verificador reduz `Gen.pop(merge_gen(..))` sem precisar abrir o `Bool`.
def pick_fit(cond: Bool, +lf: U32, +rf: U32) -> U32:
  match cond:
    case True{}:
      lf
    case False{}:
      rf

def pick_gene(-G: Data, cond: Bool, lg: G, rg: G) -> G:
  match cond:
    case True{}:
      lg
    case False{}:
      rg

# Junta os dois lados numa geração só. Os dois `Gen` chegam como PARÂMETROS,
# afins e recém-construídos, então abri-los não copia nada.
def merge_gen(-G: Data, gl: Gen<G>, gr: Gen<G>) -> Gen<G>:
  match gl gr:
    case Gen{lp, lf, lg} Gen{rp, rf, rg}:
      +lf = lf
      +rf = rf
      +cond = U32.is_ge(lf, rf)
      Gen{T.Node{lp, rp}, pick_fit(cond, lf, rf), pick_gene(G, cond, lg, rg)}

def init_gen(-G: Data, tree: T.PopTree<Ind<G>>, champ: Ind<G>) -> Gen<G>:
  match champ:
    case Ind{cg, cf}:
      Gen{tree, cf, cg}

def leaf_gen(-G: Data, +gene: G, +fit: U32) -> Gen<G>:
  Gen{T.Leaf{Ind{gene, fit}}, fit, gene}

# Gera a primeira geração: população de profundidade d (2^d indivíduos) COM o
# campeão já descoberto, na mesma travessia — mesmo princípio de `breed_tree`.
# `merge_gen` compara aptidões soltas subindo a recursão, então nenhum `Ind`
# compartilhado é aberto e nada é percorrido duas vezes.
def first_gen(~G: Type, ~init: U32 -> G, ~fit: G -> U32,
              d: Nat, +seed: U32) -> Gen<G>:
  match d:
    case 0n:
      +g = init(seed)
      leaf_gen(G, g, fit(g))
    case 1n+ +p:
      +seed = seed
      l r = first_gen(~G, ~init, ~fit, p, R.split.fst(seed)) first_gen(~G, ~init, ~fit, p, R.split.snd(seed))
      merge_gen(G, l, r)

# Só a árvore, para quem não quer o campeão
def gen_population(~G: Type, ~init: U32 -> G, ~fit: G -> U32,
                   d: Nat, +seed: U32) -> T.PopTree<Ind<G>>:
  Gen.pop(G, first_gen(~G, ~init, ~fit, d, seed))

# Reproduz a população inteira em UMA travessia, fazendo de uma vez só:
#   1. o cruzamento de cada indivíduo com o campeão,
#   2. a injeção do elitismo (a folha mais à esquerda recebe o campeão
#      intacto, em vez de ser criada e depois sobrescrita),
#   3. a descoberta do campeão da nova geração.
#
# `on_elite` marca o caminho até a folha de elite: verdadeiro na raiz, herdado
# pelo filho esquerdo e falso no direito. Como o campeão ocupa aquela folha,
# o máximo calculado aqui é o máximo da população resultante — exatamente o
# que `best_ind(inject_elite(...))` devolvia antes.
def breed_leaf(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
               ind: Ind<G>, on_elite: Bool,
               +seed: U32, +champ_f: U32, +champ_g: G) -> Gen<G>:
  match on_elite:
    case True{}:
      # slot de elite: o campeão sobrevive intacto (elitismo estrito)
      Gen{T.Leaf{Ind{champ_g, champ_f}}, champ_f, champ_g}
    case False{}:
      +parent_g = Ind.gene(G, ind)
      +child_g = repro(parent_g, champ_g, seed)
      +child_f = fit(child_g)
      Gen{T.Leaf{Ind{child_g, child_f}}, child_f, child_g}

def breed_tree(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
               tree: T.PopTree<Ind<G>>, on_elite: Bool,
               +seed: U32, +champ_f: U32, +champ_g: G) -> Gen<G>:
  match tree:
    case T.Leaf{ind}:
      breed_leaf(~G, ~repro, ~fit, ind, on_elite, seed, champ_f, champ_g)
    case T.Node{left, right}:
      +seed = seed; +champ_f = champ_f; +champ_g = champ_g
      gl = breed_tree(~G, ~repro, ~fit, left, on_elite, R.split.fst(seed), champ_f, champ_g)
      gr = breed_tree(~G, ~repro, ~fit, right, False{}, R.split.snd(seed), champ_f, champ_g)
      merge_gen(G, gl, gr)

def leaf_from_ind(-G: Data, ind: Ind<G>) -> Gen<G>:
  match ind:
    case Ind{+cg, +cf}:
      Gen{T.Leaf{Ind{cg, cf}}, cf, cg}

# Variante para operadores que já calculam a aptidão do filho internamente
# (cenários meméticos como GP, Sudoku e DE), eliminando a 3ª avaliação redundante.
def breed_leaf_eval(~G: Type, ~repro: G -> G -> U32 -> Ind<G>,
                    ind: Ind<G>, on_elite: Bool,
                    +seed: U32, +champ_f: U32, +champ_g: G) -> Gen<G>:
  match on_elite:
    case True{}:
      Gen{T.Leaf{Ind{champ_g, champ_f}}, champ_f, champ_g}
    case False{}:
      +parent_g = Ind.gene(G, ind)
      leaf_from_ind(G, repro(parent_g, champ_g, seed))

def breed_tree_eval(~G: Type, ~repro: G -> G -> U32 -> Ind<G>,
                    tree: T.PopTree<Ind<G>>, on_elite: Bool,
                    +seed: U32, +champ_f: U32, +champ_g: G) -> Gen<G>:
  match tree:
    case T.Leaf{ind}:
      breed_leaf_eval(~G, ~repro, ind, on_elite, seed, champ_f, champ_g)
    case T.Node{left, right}:
      +seed = seed; +champ_f = champ_f; +champ_g = champ_g
      gl = breed_tree_eval(~G, ~repro, left, on_elite, R.split.fst(seed), champ_f, champ_g)
      gr = breed_tree_eval(~G, ~repro, right, False{}, R.split.snd(seed), champ_f, champ_g)
      merge_gen(G, gl, gr)

# ----------------------------------------------------------------
# SELEÇÃO POR TORNEIO
# ----------------------------------------------------------------
# O motor original (Rust) escolhe cada pai por torneio: sorteia `tsize`
# indivíduos e fica com o melhor. Aqui a população é uma árvore binária
# perfeita, então sortear um indivíduo é descer `d` níveis escolhendo o lado
# por um bit aleatório — O(log N) e sem índice nenhum.
#
# `go_right` é o bit do nível ATUAL, calculado no passo anterior e recebido
# como parâmetro: `match` não escrutina valor computado (Armadilha 5).
def is_odd(+x: U32) -> Bool:
  Bool.not(U32.is_even(x))

def sample.go(-G: Data, t: T.PopTree<Ind<G>>, go_right: Bool, +bits: U32) -> Ind<G>:
  match t go_right:
    case T.Leaf{ind} True{}:
      ind
    case T.Leaf{ind} False{}:
      ind
    case T.Node{left, right} True{}:
      +rest = U32.shrn(bits, 1n)
      sample.go(G, right, is_odd(rest), rest)
    case T.Node{left, right} False{}:
      +rest = U32.shrn(bits, 1n)
      sample.go(G, left, is_odd(rest), rest)

# Um indivíduo sorteado uniformemente: cada bit de `bits` escolhe um nível
def sample(-G: Data, t: T.PopTree<Ind<G>>, +bits: U32) -> Ind<G>:
  sample.go(G, t, is_odd(bits), bits)

def tournament.go(-G: Data, k: Nat, +pop: T.PopTree<Ind<G>>,
                  +best: Ind<G>, +seed: U32) -> Ind<G>:
  match k:
    case 0n:
      best
    case 1n+p:
      +s = R.step(seed)
      tournament.go(G, p, pop, pick_better(G, best, sample(G, pop, s)), R.step(s))

# Melhor de `k` sorteios. `k = 1n` degenera em seleção aleatória pura;
# quanto maior `k`, maior a pressão seletiva.
def tournament(-G: Data, k: Nat, +pop: T.PopTree<Ind<G>>, +seed: U32) -> Ind<G>:
  tournament.go(G, k, pop, sample(G, pop, seed), R.step(seed))

# ----------------------------------------------------------------
# REPRODUÇÃO COM SELEÇÃO POR TORNEIO
# ----------------------------------------------------------------
# Diferença para `breed_tree`: lá todo indivíduo cruza com o campeão (pressão
# máxima, diversidade mínima); aqui os DOIS pais saem de torneios na geração
# anterior, como no motor em Rust. O indivíduo que ocupava a folha é
# descartado — a geração nova é formada só por filhos, mais o elite.
def breed_leaf_tourney(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                       on_elite: Bool, +seed: U32, +champ_f: U32, +champ_g: G,
                       +pop: T.PopTree<Ind<G>>, +tsize: Nat) -> Gen<G>:
  match on_elite:
    case True{}:
      Gen{T.Leaf{Ind{champ_g, champ_f}}, champ_f, champ_g}
    case False{}:
      +p1 = Ind.gene(G, tournament(G, tsize, pop, R.split.fst(seed)))
      +p2 = Ind.gene(G, tournament(G, tsize, pop, R.split.snd(seed)))
      +child_g = repro(p1, p2, seed)
      +child_f = fit(child_g)
      Gen{T.Leaf{Ind{child_g, child_f}}, child_f, child_g}

def breed_tourney(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                  shape: T.PopTree<Ind<G>>, on_elite: Bool,
                  +seed: U32, +champ_f: U32, +champ_g: G,
                  +pop: T.PopTree<Ind<G>>, +tsize: Nat) -> Gen<G>:
  match shape:
    case T.Leaf{ind}:
      breed_leaf_tourney(~G, ~repro, ~fit, on_elite, seed, champ_f, champ_g, pop, tsize)
    case T.Node{left, right}:
      +seed = seed; +champ_f = champ_f; +champ_g = champ_g
      gl = breed_tourney(~G, ~repro, ~fit, left, on_elite, R.split.fst(seed), champ_f, champ_g, pop, tsize)
      gr = breed_tourney(~G, ~repro, ~fit, right, False{}, R.split.snd(seed), champ_f, champ_g, pop, tsize)
      merge_gen(G, gl, gr)

def run_gen_loop_tourney(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                         g: Nat, gen: Gen<G>, +seed: U32, +tsize: Nat) -> Gen<G>:
  match g:
    case 0n:
      gen
    case 1n+p:
      match gen:
        case Gen{tree, cf, cg}:
          +tree = tree
          +next_seed = R.split.trd(seed)
          run_gen_loop_tourney(~G, ~repro, ~fit, p,
                               breed_tourney(~G, ~repro, ~fit, tree, True{}, seed, cf, cg, tree, tsize),
                               next_seed, tsize)

# Laço geracional: o campeão atravessa as gerações dentro do `Gen`, então
# `best_ind` é chamado uma vez por ilha e não uma vez por geração.
def run_gen_loop(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                 g: Nat, gen: Gen<G>, +seed: U32) -> Gen<G>:
  match g:
    case 0n:
      gen
    case 1n+p:
      match gen:
        case Gen{tree, cf, cg}:
          +next_seed = R.split.trd(seed)
          run_gen_loop(~G, ~repro, ~fit, p,
                       breed_tree(~G, ~repro, ~fit, tree, True{}, seed, cf, cg),
                       next_seed)

def run_gen_loop_eval(~G: Type, ~repro: G -> G -> U32 -> Ind<G>,
                      g: Nat, gen: Gen<G>, +seed: U32) -> Gen<G>:
  match g:
    case 0n:
      gen
    case 1n+p:
      match gen:
        case Gen{tree, cf, cg}:
          +next_seed = R.split.trd(seed)
          run_gen_loop_eval(~G, ~repro, p,
                            breed_tree_eval(~G, ~repro, tree, True{}, seed, cf, cg),
                            next_seed)

# Executa g gerações evolutivas sequencialmente na ilha local
def run_generations(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                    g: Nat, +tree: T.PopTree<Ind<G>>, +seed: U32) -> T.PopTree<Ind<G>>:
  Gen.pop(G, run_gen_loop(~G, ~repro, ~fit, g, init_gen(G, tree, best_ind(G, tree)), seed))

def run_generations_eval(~G: Type, ~repro: G -> G -> U32 -> Ind<G>,
                         g: Nat, +tree: T.PopTree<Ind<G>>, +seed: U32) -> T.PopTree<Ind<G>>:
  Gen.pop(G, run_gen_loop_eval(~G, ~repro, g, init_gen(G, tree, best_ind(G, tree)), seed))

# ----------------------------------------------------------------
# MODELO DE ARQUIPÉLAGO MULTI-ILHAS (PGA COARSE-GRAINED)
# ----------------------------------------------------------------

type ArchTree<-G: Data> is Data:
  SingleIsland{gen: Gen<G>}
  ArchBranch{left: ArchTree<G>, right: ArchTree<G>}

# Gera um arquipélago com 2^d ilhas independentes, cada uma com 2^pop_d indivíduos
def gen_archipelago(~G: Type, ~init: U32 -> G, ~fit: G -> U32,
                    d: Nat, +seed: U32, pop_d: Nat) -> ArchTree<G>:
  match d:
    case 0n:
      +pop = gen_population(~G, ~init, ~fit, pop_d, seed)
      SingleIsland{init_gen(G, pop, best_ind(G, pop))}
    case 1n+ +p:
      +seed = seed; +pop_d = pop_d
      l r = gen_archipelago(~G, ~init, ~fit, p, R.split.fst(seed), pop_d) gen_archipelago(~G, ~init, ~fit, p, R.split.snd(seed), pop_d)
      ArchBranch{l, r}

# Campeão global absoluto somando todas as ilhas do arquipélago.
# A redução bifurca no nível do arquipélago em O(1) por ilha (lê bfit/bgene
# já computados na travessia fundida, sem re-percorrer a árvore local).
def best_archipelago(-G: Data, +arch: ArchTree<G>) -> Ind<G>:
  match arch:
    case SingleIsland{gen}:
      Gen{_, bfit, bgene} = gen
      Ind{bgene, bfit}
    case ArchBranch{left, right}:
      bl br = best_archipelago(G, left) best_archipelago(G, right)
      pick_better(G, bl, br)

# Contagem estrutural de ilhas do arquipélago (base das leis de topologia)
def arch_island_count(-G: Data, arch: ArchTree<G>) -> Nat:
  match arch:
    case SingleIsland{gen}:
      1n
    case ArchBranch{left, right}:
      Nat.add(arch_island_count(G, left), arch_island_count(G, right))

# Evolução concorrente de todas as ilhas por uma época de e gerações
def evolve_archipelago(~G: Type, ~repro: G -> G -> U32 -> G, ~fit: G -> U32,
                       arch: ArchTree<G>, +seed: U32, e: Nat) -> ArchTree<G>:
  match arch:
    case SingleIsland{gen}:
      SingleIsland{run_gen_loop(~G, ~repro, ~fit, e, gen, seed)}
    case ArchBranch{left, right}:
      +seed = seed; +e = e
      l r = evolve_archipelago(~G, ~repro, ~fit, left, R.split.fst(seed), e) evolve_archipelago(~G, ~repro, ~fit, right, R.split.snd(seed), e)
      ArchBranch{l, r}

# Migração do campeão global para o slot de elite de cada ilha
def migrate_champion(-G: Data, arch: ArchTree<G>, +champ: Ind<G>) -> ArchTree<G>:
  match arch:
    case SingleIsland{gen}:
      Gen{pop, _, _} = gen
      Ind{cg, cf} = champ
      SingleIsland{Gen{pop, cf, cg}}
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
      +next_seed = R.split.trd(seed); +e = e
      +evolved = evolve_archipelago(~G, ~repro, ~fit, arch, seed, e)
      +champ = best_archipelago(G, evolved)
      +migrated = migrate_champion(G, evolved, champ)
      run_archipelago(~G, ~repro, ~fit, p, migrated, next_seed, e)

def evolve_archipelago_eval(~G: Type, ~repro: G -> G -> U32 -> Ind<G>,
                            arch: ArchTree<G>, +seed: U32, e: Nat) -> ArchTree<G>:
  match arch:
    case SingleIsland{gen}:
      SingleIsland{run_gen_loop_eval(~G, ~repro, e, gen, seed)}
    case ArchBranch{left, right}:
      +seed = seed; +e = e
      l r = evolve_archipelago_eval(~G, ~repro, left, R.split.fst(seed), e) evolve_archipelago_eval(~G, ~repro, right, R.split.snd(seed), e)
      ArchBranch{l, r}

def run_archipelago_eval(~G: Type, ~repro: G -> G -> U32 -> Ind<G>,
                         epochs: Nat, arch: ArchTree<G>, +seed: U32, e: Nat) -> ArchTree<G>:
  match epochs:
    case 0n:
      arch
    case 1n+p:
      +next_seed = R.split.trd(seed); +e = e
      +evolved = evolve_archipelago_eval(~G, ~repro, arch, seed, e)
      +champ = best_archipelago(G, evolved)
      +migrated = migrate_champion(G, evolved, champ)
      run_archipelago_eval(~G, ~repro, p, migrated, next_seed, e)
