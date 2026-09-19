import Base
import ./../utils/random.bend as R
import ./utils/poptree.bend as T
import ./stats.bend as S

# ================================================================
# BEND 2 GENERIC GENETIC ALGORITHM ENGINE (ga.bend)
# ================================================================
# Porte do motor em Rust (`rust-wasm/src/genetic/ga.rs`).
#
# O motor é polimórfico sobre dois tipos, ambos opacos para ele:
#   P — o contexto do problema (o `&self` do Rust: cidades, dicas do sudoku,
#       tamanho do genoma...). Somente leitura, compartilhado por todas as
#       tarefas.
#   G — o genoma.
#
# O problema fornece quatro templates, como os métodos do trait `GAProblem`:
#   ~init   : P -> U32 -> G                (random_genes)
#   ~fit    : P -> G -> U32                (fitness; maior é melhor)
#   ~cross  : P -> G -> G -> U32 -> G      (crossover)
#   ~mutate : P -> G -> U32 -> U32 -> G    (mutate: ctx, genes, taxa por gene, semente)
#
# O motor cuida do resto, como o `GeneticAlgorithm` do Rust: seleção por
# torneio, elitismo, taxas de cruzamento e mutação, controle de estagnação
# adaptativo e parada ao atingir a aptidão máxima.
#
# A população é uma árvore binária de 2^d indivíduos (fork-join) e o
# paralelismo vem do ARQUIPÉLAGO: ilhas independentes evoluem em paralelo e o
# campeão global migra entre elas a cada época. Torneio sobre uma população
# compartilhada entre tarefas não escala na HVM (veja o README).
#
# Parâmetros template `~` vêm SEMPRE antes dos demais, com os tipos primeiro:
# o backend nativo precisa deles declarados antes de serem citados.
# ================================================================

# ----------------------------------------------------------------
# INDIVÍDUO
# ----------------------------------------------------------------

type Ind<-G: Data> is Data:
  Ind{gene: G, fit: U32}

def Ind.gene(-G: Data, ind: Ind<G>) -> G:
  Ind{g, _} = ind
  g

def Ind.fit(-G: Data, ind: Ind<G>) -> U32:
  Ind{_, f} = ind
  f

def pick_better(-G: Data, +a: Ind<G>, +b: Ind<G>) -> Ind<G>:
  Bool.pick(Ind<G>, U32.is_ge(Ind.fit(G, a), Ind.fit(G, b)), a, b)

# Estatísticas agregadas (melhor, pior, soma, N) em uma travessia paralela
def population_stats(-G: Data, +tree: T.PopTree<Ind<G>>) -> S.PopStats:
  match tree:
    case T.Leaf{ind}:
      S.leaf_stats(Ind.fit(G, ind))
    case T.Node{left, right}:
      sl sr = population_stats(G, left) population_stats(G, right)
      S.merge_stats(sl, sr)

# ----------------------------------------------------------------
# CONFIGURAÇÃO (GAConfig)
# ----------------------------------------------------------------
# Taxas são limiares sobre 2^32 (`R.per(num, den)`).
#   cross_rate : chance de cruzar os dois pais (senão o filho clona o pai 1)
#   mut_rate   : chance de mutar o filho
#   gene_rate  : taxa por gene, repassada ao `~mutate` do problema
#   tsize      : tamanho do torneio
#   max_stag   : gerações sem melhora antes de reiniciar (0 = sem controle)
#   max_fit    : aptidão que encerra a busca (0 = nenhuma)
#   pop_d      : profundidade da população de cada ilha (2^pop_d indivíduos)
type Config is Data:
  Config{cross_rate: U32, mut_rate: U32, gene_rate: U32, tsize: U32,
         max_stag: U32, max_fit: U32, pop_d: U32}

def config(+cross_rate: U32, +mut_rate: U32, +gene_rate: U32, +tsize: U32,
           +max_stag: U32, +max_fit: U32, +pop_d: U32) -> Config:
  Config{cross_rate, mut_rate, gene_rate, tsize, max_stag, max_fit, pop_d}

def Config.pop_d(c: Config) -> Nat:
  Config{_, _, _, _, _, _, d} = c
  U32.to_nat(d)

def Config.max_stag(c: Config) -> U32:
  Config{_, _, _, _, m, _, _} = c
  m

def Config.max_fit(c: Config) -> U32:
  Config{_, _, _, _, _, m, _} = c
  m

# ----------------------------------------------------------------
# GERAÇÃO: população + campeão descoberto na mesma travessia
# ----------------------------------------------------------------
# O campeão sobe a recursão como aptidão e genoma SOLTOS, não como `Ind`.
# Medido com 2,56 milhões de indivíduos: achar o campeão abrindo registros
# `Ind` compartilhados custava 9x mais que reproduzir a população inteira —
# destruir um nó compartilhado obriga o runtime a copiá-lo. Aqui comparar é
# aritmética escalar, e o campeão sai de graça da travessia que gera os filhos.
type Gen<-G: Data> is Data:
  Gen{pop: T.PopTree<Ind<G>>, bfit: U32, bgene: G}

def Gen.pop(-G: Data, g: Gen<G>) -> T.PopTree<Ind<G>>:
  Gen{p, _, _} = g
  p

def Gen.best(-G: Data, g: Gen<G>) -> Ind<G>:
  Gen{_, bf, bg} = g
  Ind{bg, bf}

def Gen.bfit(-G: Data, g: Gen<G>) -> U32:
  Gen{_, bf, _} = g
  bf

def Gen.bgene(-G: Data, g: Gen<G>) -> G:
  Gen{_, _, bg} = g
  bg

# Troca o campeão registrado. Como o slot de elite da próxima geração recebe
# o campeão, isto REINTRODUZ um indivíduo na população (usado pela migração
# e pela reintrodução do melhor durante a estagnação).
def Gen.with_champ(-G: Data, g: Gen<G>, +f: U32, bgene: G) -> Gen<G>:
  Gen{p, _, _} = g
  Gen{p, f, bgene}

# Seletores do campeão: devolvem só aptidão e genoma, a população fica FORA
# do ramo condicional. Assim `Gen.pop(merge_gen(..))` reduz sem abrir o
# `Bool` — é o que torna a Lei 13 demonstrável.
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

# Junta duas meias-gerações. Os dois `Gen` chegam como parâmetros afins e
# recém-construídos, então abri-los não copia nada.
def merge_gen(-G: Data, gl: Gen<G>, gr: Gen<G>) -> Gen<G>:
  match gl gr:
    case Gen{lp, lf, lg} Gen{rp, rf, rg}:
      +lf = lf
      +rf = rf
      +cond = U32.is_ge(lf, rf)
      Gen{T.Node{lp, rp}, pick_fit(cond, lf, rf), pick_gene(G, cond, lg, rg)}

def leaf_gen(-G: Data, +gene: G, +fit: U32) -> Gen<G>:
  Gen{T.Leaf{Ind{gene, fit}}, fit, gene}

# População inicial aleatória de 2^d indivíduos, em paralelo
def first_gen(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
              d: Nat, +ctx: P, +seed: U32) -> Gen<G>:
  match d:
    case 0n:
      +g = init(ctx, seed)
      leaf_gen(G, g, fit(ctx, g))
    case 1n+ +p:
      l r = first_gen(~P, ~G, ~init, ~fit, p, ctx, R.split.fst(seed)) first_gen(~P, ~G, ~init, ~fit, p, ctx, R.split.snd(seed))
      merge_gen(G, l, r)

# ----------------------------------------------------------------
# SELEÇÃO POR TORNEIO (tournament_selection)
# ----------------------------------------------------------------
# Sortear um indivíduo é descer d níveis escolhendo o lado por um bit
# aleatório — O(log N), sem índice. `go_right` é o bit do nível atual,
# calculado no passo anterior (match não escrutina valor computado).

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

def sample(-G: Data, t: T.PopTree<Ind<G>>, +bits: U32) -> Ind<G>:
  +bits = R.mix(bits)
  sample.go(G, t, is_odd(bits), bits)

def tournament.go(-G: Data, k: Nat, +pop: T.PopTree<Ind<G>>,
                  +best: Ind<G>, +seed: U32) -> Ind<G>:
  match k:
    case 0n:
      best
    case 1n+p:
      +s = R.step(seed)
      tournament.go(G, p, pop, pick_better(G, best, sample(G, pop, s)), R.step(s))

# Melhor de `k` sorteios (k = 1 degenera em seleção aleatória)
def tournament(-G: Data, k: Nat, +pop: T.PopTree<Ind<G>>, +seed: U32) -> Ind<G>:
  tournament.go(G, (k - 1n : Nat), pop, sample(G, pop, seed), R.step(seed))

# ----------------------------------------------------------------
# REPRODUÇÃO (run_generation)
# ----------------------------------------------------------------

# Taxas efetivas de UMA geração, já com os multiplicadores de estagnação
type Eff is Data:
  Eff{tsize: Nat, cross_rate: U32, mut_rate: U32, gene_rate: U32}

def cross_maybe(~P: Data, ~G: Data, ~cross: P -> G -> G -> U32 -> G,
                hit: Bool, +ctx: P, p1: G, p2: G, +seed: U32) -> G:
  match hit:
    case True{}:
      cross(ctx, p1, p2, seed)
    case False{}:
      p1

def mutate_maybe(~P: Data, ~G: Data, ~mutate: P -> G -> U32 -> U32 -> G,
                 hit: Bool, +ctx: P, g: G, +rate: U32, +seed: U32) -> G:
  match hit:
    case True{}:
      mutate(ctx, g, rate, seed)
    case False{}:
      g

# Uma folha da nova geração. A folha mais à esquerda (`on_elite`) recebe o
# campeão intacto (elitismo estrito, o `offspring[0]` do Rust); as demais
# recebem um filho de dois pais escolhidos por torneio na geração anterior.
def breed_leaf(~P: Data, ~G: Data, ~fit: P -> G -> U32,
               ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
               on_elite: Bool, +ctx: P, +seed: U32, +champ_f: U32, +champ_g: G,
               +pop: T.PopTree<Ind<G>>, +eff: Eff) -> Gen<G>:
  match on_elite:
    case True{}:
      Gen{T.Leaf{Ind{champ_g, champ_f}}, champ_f, champ_g}
    case False{}:
      Eff{ts, cr, mr, gr} = eff
      +ts = ts
      p1 = Ind.gene(G, tournament(G, ts, pop, R.split.fst(seed)))
      p2 = Ind.gene(G, tournament(G, ts, pop, R.split.snd(seed)))
      +s4 = R.split.fth(seed)
      +child = mutate_maybe(~P, ~G, ~mutate, R.hit(R.split.trd(seed), mr), ctx,
                 cross_maybe(~P, ~G, ~cross, R.hit(seed, cr), ctx, p1, p2, s4),
                 gr, R.step(s4))
      +f = fit(ctx, child)
      Gen{T.Leaf{Ind{child, f}}, f, child}

# Gera a próxima população com a forma da anterior. As duas metades são uma
# CHAMADA PARALELA: sem ela, tudo roda num núcleo só.
def breed(~P: Data, ~G: Data, ~fit: P -> G -> U32,
          ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
          shape: T.PopTree<Ind<G>>, on_elite: Bool, +ctx: P, +seed: U32,
          +champ_f: U32, +champ_g: G, +pop: T.PopTree<Ind<G>>, +eff: Eff) -> Gen<G>:
  match shape:
    case T.Leaf{ind}:
      breed_leaf(~P, ~G, ~fit, ~cross, ~mutate, on_elite, ctx, seed, champ_f, champ_g, pop, eff)
    case T.Node{left, right}:
      gl gr = breed(~P, ~G, ~fit, ~cross, ~mutate, left, on_elite, ctx, R.split.fst(seed), champ_f, champ_g, pop, eff) breed(~P, ~G, ~fit, ~cross, ~mutate, right, False{}, ctx, R.split.snd(seed), champ_f, champ_g, pop, eff)
      merge_gen(G, gl, gr)

def next_gen(~P: Data, ~G: Data, ~fit: P -> G -> U32,
             ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
             gen: Gen<G>, +ctx: P, +eff: Eff, +seed: U32) -> Gen<G>:
  match gen:
    case Gen{+tree, cf, cg}:
      breed(~P, ~G, ~fit, ~cross, ~mutate, tree, True{}, ctx, seed, cf, cg, tree, eff)

# ----------------------------------------------------------------
# ILHA COM CONTROLE DE ESTAGNAÇÃO (o laço `run` do Rust)
# ----------------------------------------------------------------
# Estado de uma população entre gerações:
#   gen        — a população atual e seu campeão
#   best_f/g   — o melhor já encontrado (sobrevive a um reinício)
#   stag_start — geração da última melhora
#   stag_fit   — aptidão da última melhora (0 = nenhuma, após reinício)
#   generation — contador de gerações
type Island<-G: Data> is Data:
  Island{gen: Gen<G>, best_f: U32, best_g: G, stag_start: U32, stag_fit: U32, generation: U32}

def island(-G: Data, +gen: Gen<G>) -> Island<G>:
  +f = Gen.bfit(G, gen)
  Island{gen, f, Gen.bgene(G, gen), 0, f, 0}

def Island.best(-G: Data, isl: Island<G>) -> Ind<G>:
  Island{_, bf, bg, _, _, _} = isl
  Ind{bg, bf}

def Island.best_f(-G: Data, isl: Island<G>) -> U32:
  Island{_, bf, _, _, _, _} = isl
  bf

def Island.generation(-G: Data, isl: Island<G>) -> U32:
  Island{_, _, _, _, _, g} = isl
  g

def Island.stag_start(-G: Data, isl: Island<G>) -> U32:
  Island{_, _, _, ss, _, _} = isl
  ss

def Island.pop(-G: Data, isl: Island<G>) -> T.PopTree<Ind<G>>:
  Island{gen, _, _, _, _, _} = isl
  Gen.pop(G, gen)

# Multiplica uma taxa (limiar) por `m`, saturando em 2^32 - 1
def scale(+rate: U32, +m: F32) -> U32:
  F32.to_u32(F32.min((U32.to_f32(rate) * m : F32), {4294967040.0 : F32}))

# Controle de estagnação adaptativo, como no Rust: depois de max_stag/2
# gerações sem melhora, a mutação cresce até 2x (e além) e o torneio encolhe
# até 2, para tentar escapar do platô.
def effective(+cfg: Config, +stagnated: U32) -> Eff:
  Config{cr, mr, gr, ts, ms, _, _} = cfg
  +half = U32.max(U32.div(ms, 2), 1)
  +excess = Bool.pick(U32, Bool.or(U32.is_zero(ms), U32.is_le(stagnated, half)), 0, (stagnated - half : U32))
  +ratio = (U32.to_f32(excess) / U32.to_f32(half) : F32)
  +mult = ({1.0 : F32} + ratio : F32)
  +tmult = ({1.0 : F32} - F32.min(ratio, {1.0 : F32}) : F32)
  +tsize = U32.max(F32.to_u32((U32.to_f32(ts) * tmult : F32)), 2)
  Eff{U32.to_nat(tsize), cr, scale(mr, mult), scale(gr, mult)}

# Depois de uma geração sem melhora. `reset` = passou de max_stag gerações:
# reinicia a população (o melhor já encontrado continua guardado);
# `reintro` = exatamente max_stag/2: reintroduz o melhor na população.
def stagnate(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
             reset: Bool, reintro: Bool, gen: Gen<G>, +ctx: P, +cfg: Config,
             +bf: U32, +bg: G, +ss: U32, +sf: U32, +g: U32, +seed: U32) -> Island<G>:
  match reset reintro:
    case True{} True{}:
      Island{first_gen(~P, ~G, ~init, ~fit, Config.pop_d(cfg), ctx, seed), bf, bg, g, 0, U32.inc(g)}
    case True{} False{}:
      Island{first_gen(~P, ~G, ~init, ~fit, Config.pop_d(cfg), ctx, seed), bf, bg, g, 0, U32.inc(g)}
    case False{} True{}:
      Island{Gen.with_champ(G, gen, bf, bg), bf, bg, ss, sf, U32.inc(g)}
    case False{} False{}:
      Island{gen, bf, bg, ss, sf, U32.inc(g)}

def after_gen(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
              improved: Bool, gen: Gen<G>, +ctx: P, +cfg: Config, +cur: U32,
              +bf: U32, +bg: G, +ss: U32, +sf: U32, +g: U32, +seed: U32) -> Island<G>:
  match improved:
    case True{}:
      Island{gen, bf, bg, g, cur, U32.inc(g)}
    case False{}:
      +ms = Config.max_stag(cfg)
      +stagnated = (g - ss : U32)
      +active = Bool.not(U32.is_zero(ms))
      stagnate(~P, ~G, ~init, ~fit,
               Bool.and(active, U32.is_gt(stagnated, ms)),
               Bool.and(active, U32.is_eq(stagnated, U32.max(U32.div(ms, 2), 1))),
               gen, ctx, cfg, bf, bg, ss, sf, g, seed)

# Uma geração completa: reprodução, registro do melhor e estagnação
def island_step(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
                ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
                isl: Island<G>, +ctx: P, +cfg: Config, +seed: U32) -> Island<G>:
  match isl:
    case Island{gen, +bf, bg, +ss, +sf, +g}:
      +gen2 = next_gen(~P, ~G, ~fit, ~cross, ~mutate, gen, ctx, effective(cfg, (g - ss : U32)), seed)
      +cur = Gen.bfit(G, gen2)
      +better = U32.is_gt(cur, bf)
      after_gen(~P, ~G, ~init, ~fit, U32.is_gt(cur, sf), gen2, ctx, cfg, cur,
                pick_fit(better, cur, bf), pick_gene(G, better, Gen.bgene(G, gen2), bg),
                ss, sf, g, R.split.trd(seed))

# Encerra quando o melhor atinge a aptidão máxima configurada
def is_done(-G: Data, +cfg: Config, +isl: Island<G>) -> Bool:
  +mf = Config.max_fit(cfg)
  Bool.and(Bool.not(U32.is_zero(mf)), U32.is_ge(Island.best_f(G, isl), mf))

def island_loop(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
                ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
                k: Nat, isl: Island<G>, done: Bool, +ctx: P, +cfg: Config, +seed: U32) -> Island<G>:
  match k done:
    case 0n True{}:
      isl
    case 0n False{}:
      isl
    case 1n+p True{}:
      isl
    case 1n+p False{}:
      +isl2 = island_step(~P, ~G, ~init, ~fit, ~cross, ~mutate, isl, ctx, cfg, seed)
      island_loop(~P, ~G, ~init, ~fit, ~cross, ~mutate, p, isl2, is_done(G, cfg, isl2), ctx, cfg, R.split.fth(seed))

# Uma população nova, aleatória
def new_island(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
               +ctx: P, +cfg: Config, +seed: U32) -> Island<G>:
  island(G, first_gen(~P, ~G, ~init, ~fit, Config.pop_d(cfg), ctx, seed))

# Evolui uma população isolada por até `k` gerações
def run_island(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
               ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
               k: Nat, +isl: Island<G>, +ctx: P, +cfg: Config, +seed: U32) -> Island<G>:
  island_loop(~P, ~G, ~init, ~fit, ~cross, ~mutate, k, isl, is_done(G, cfg, isl), ctx, cfg, seed)

# ----------------------------------------------------------------
# ARQUIPÉLAGO (paralelismo entre ilhas)
# ----------------------------------------------------------------

type ArchTree<-G: Data> is Data:
  SingleIsland{isl: Island<G>}
  ArchBranch{left: ArchTree<G>, right: ArchTree<G>}

# 2^d ilhas independentes
def gen_archipelago(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
                    d: Nat, +ctx: P, +cfg: Config, +seed: U32) -> ArchTree<G>:
  match d:
    case 0n:
      SingleIsland{new_island(~P, ~G, ~init, ~fit, ctx, cfg, seed)}
    case 1n+ +p:
      l r = gen_archipelago(~P, ~G, ~init, ~fit, p, ctx, cfg, R.split.fst(seed)) gen_archipelago(~P, ~G, ~init, ~fit, p, ctx, cfg, R.split.snd(seed))
      ArchBranch{l, r}

# O melhor de todas as ilhas (lê o `best` já guardado em cada uma)
def best_archipelago(-G: Data, +arch: ArchTree<G>) -> Ind<G>:
  match arch:
    case SingleIsland{isl}:
      Island.best(G, isl)
    case ArchBranch{left, right}:
      bl br = best_archipelago(G, left) best_archipelago(G, right)
      pick_better(G, bl, br)

# Contagem estrutural de ilhas (base das leis de topologia)
def arch_island_count(-G: Data, arch: ArchTree<G>) -> Nat:
  match arch:
    case SingleIsland{isl}:
      1n
    case ArchBranch{left, right}:
      Nat.add(arch_island_count(G, left), arch_island_count(G, right))

# Todas as ilhas evoluem `e` gerações em paralelo
def evolve_archipelago(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
                       ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
                       arch: ArchTree<G>, +e: Nat, +ctx: P, +cfg: Config, +seed: U32) -> ArchTree<G>:
  match arch:
    case SingleIsland{isl}:
      SingleIsland{run_island(~P, ~G, ~init, ~fit, ~cross, ~mutate, e, isl, ctx, cfg, seed)}
    case ArchBranch{left, right}:
      l r = evolve_archipelago(~P, ~G, ~init, ~fit, ~cross, ~mutate, left, e, ctx, cfg, R.split.fst(seed)) evolve_archipelago(~P, ~G, ~init, ~fit, ~cross, ~mutate, right, e, ctx, cfg, R.split.snd(seed))
      ArchBranch{l, r}

# O campeão global vira o campeão (e portanto o elite) de todas as ilhas
def migrate_champion(-G: Data, arch: ArchTree<G>, +champ: Ind<G>) -> ArchTree<G>:
  match arch:
    case SingleIsland{isl}:
      Island{gen, _, _, ss, sf, g} = isl
      Ind{cg, cf} = champ
      SingleIsland{Island{Gen.with_champ(G, gen, cf, cg), cf, cg, ss, sf, g}}
    case ArchBranch{left, right}:
      l r = migrate_champion(G, left, champ) migrate_champion(G, right, champ)
      ArchBranch{l, r}

def arch_done(-G: Data, +cfg: Config, +arch: ArchTree<G>) -> Bool:
  +mf = Config.max_fit(cfg)
  Bool.and(Bool.not(U32.is_zero(mf)), U32.is_ge(Ind.fit(G, best_archipelago(G, arch)), mf))

def run_archipelago.go(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
                       ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
                       epochs: Nat, arch: ArchTree<G>, done: Bool, +e: Nat, +ctx: P, +cfg: Config,
                       +seed: U32) -> ArchTree<G>:
  match epochs done:
    case 0n True{}:
      arch
    case 0n False{}:
      arch
    case 1n+p True{}:
      arch
    case 1n+p False{}:
      +evolved = evolve_archipelago(~P, ~G, ~init, ~fit, ~cross, ~mutate, arch, e, ctx, cfg, seed)
      +migrated = migrate_champion(G, evolved, best_archipelago(G, evolved))
      run_archipelago.go(~P, ~G, ~init, ~fit, ~cross, ~mutate, p, migrated, arch_done(G, cfg, migrated), e, ctx, cfg, R.split.trd(seed))

# `epochs` épocas de `e` gerações por ilha, com migração do campeão global
# entre épocas; para cedo se atingir a aptidão máxima
def run_archipelago(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
                    ~cross: P -> G -> G -> U32 -> G, ~mutate: P -> G -> U32 -> U32 -> G,
                    epochs: Nat, +arch: ArchTree<G>, +e: Nat, +ctx: P, +cfg: Config,
                    +seed: U32) -> ArchTree<G>:
  run_archipelago.go(~P, ~G, ~init, ~fit, ~cross, ~mutate, epochs, arch, arch_done(G, cfg, arch), e, ctx, cfg, seed)
