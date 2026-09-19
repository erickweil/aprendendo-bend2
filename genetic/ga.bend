import Base
import ./../utils/random.bend as R
import ./utils/poptree.bend as T
import ./stats.bend as S
import ./utils/genes.bend as V

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
#   ~cross  : P -> G -> G -> U32 -> G & G  (crossover: dois pais, dois filhos)
#   ~mutate : P -> G -> U32 -> U32 -> G    (mutate: ctx, genes, taxa por gene, semente)
#
# O motor cuida do resto, como o `GeneticAlgorithm` do Rust: seleção por
# torneio, elitismo, taxas de cruzamento e mutação, controle de estagnação
# adaptativo e parada ao atingir a aptidão máxima.
#
# A população é uma árvore binária de 2^d indivíduos (fork-join) e o
# paralelismo vem do ARQUIPÉLAGO: ilhas independentes evoluem em paralelo e,
# a cada época, o melhor de cada ilha migra para a vizinha (anel). Torneio sobre uma população
# compartilhada entre tarefas não escala na HVM (veja o README).
#
# Parâmetros template `~` vêm SEMPRE antes dos demais, com os tipos primeiro:
# o backend nativo precisa deles declarados antes de serem citados.
# ================================================================

# ----------------------------------------------------------------
# INDIVÍDUO
# ----------------------------------------------------------------

# `hash` é o hash do genoma guardado junto do indivíduo, como o
# `Option<u64>` do Rust: 0 = ainda não calculado. Só é preenchido quando há
# diversity_check (na passada `dedup`), e daí em diante viaja com o
# indivíduo — o elite não é re-hasheado e o torneio exclui por hash lendo um
# campo, sem tocar no genoma.
type Ind<-G: Data> is Data:
  Ind{gene: G, fit: U32, hash: U32}

def Ind.gene(-G: Data, ind: Ind<G>) -> G:
  Ind{g, _, _} = ind
  g

def Ind.fit(-G: Data, ind: Ind<G>) -> U32:
  Ind{_, f, _} = ind
  f

def Ind.hash(-G: Data, ind: Ind<G>) -> U32:
  Ind{_, _, h} = ind
  h

# Um indivíduo com hash ainda desconhecido
def fresh_ind(-G: Data, g: G, f: U32) -> Ind<G>:
  Ind{g, f, 0}

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
#   diversity  : 1 = diversity_check (sem indivíduos idênticos na ilha)
type Config is Data:
  Config{cross_rate: U32, mut_rate: U32, gene_rate: U32, tsize: U32,
         max_stag: U32, max_fit: U32, pop_d: U32, diversity: U32}

def config(+cross_rate: U32, +mut_rate: U32, +gene_rate: U32, +tsize: U32,
           +max_stag: U32, +max_fit: U32, +pop_d: U32, +diversity: U32) -> Config:
  Config{cross_rate, mut_rate, gene_rate, tsize, max_stag, max_fit, pop_d, diversity}

def Config.pop_d(c: Config) -> Nat:
  Config{_, _, _, _, _, _, d, _} = c
  U32.to_nat(d)

def Config.max_stag(c: Config) -> U32:
  Config{_, _, _, _, m, _, _, _} = c
  m

def Config.max_fit(c: Config) -> U32:
  Config{_, _, _, _, _, m, _, _} = c
  m

def Config.diversity(c: Config) -> Bool:
  Config{_, _, _, _, _, _, _, d} = c
  Bool.not(U32.is_zero(d))

# ----------------------------------------------------------------
# GERAÇÃO: população + campeão descoberto na mesma travessia
# ----------------------------------------------------------------
# O campeão sobe a recursão como aptidão e genoma SOLTOS, não como `Ind`.
# Medido com 2,56 milhões de indivíduos: achar o campeão abrindo registros
# `Ind` compartilhados custava 9x mais que reproduzir a população inteira —
# destruir um nó compartilhado obriga o runtime a copiá-lo. Aqui comparar é
# aritmética escalar, e o campeão sai de graça da travessia que gera os filhos.
type Gen<-G: Data> is Data:
  Gen{pop: T.PopTree<Ind<G>>, bfit: U32, bgene: G, bhash: U32}

def Gen.pop(-G: Data, g: Gen<G>) -> T.PopTree<Ind<G>>:
  Gen{p, _, _, _} = g
  p

def Gen.best(-G: Data, g: Gen<G>) -> Ind<G>:
  Gen{_, bf, bg, bh} = g
  Ind{bg, bf, bh}

def Gen.bfit(-G: Data, g: Gen<G>) -> U32:
  Gen{_, bf, _, _} = g
  bf

def Gen.bgene(-G: Data, g: Gen<G>) -> G:
  Gen{_, _, bg, _} = g
  bg

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
    case Gen{lp, lf, lg, lh} Gen{rp, rf, rg, rh}:
      +lf = lf
      +rf = rf
      +cond = U32.is_ge(lf, rf)
      Gen{T.Node{lp, rp}, pick_fit(cond, lf, rf), pick_gene(G, cond, lg, rg), pick_fit(cond, lh, rh)}

def leaf_gen(-G: Data, +gene: G, +fit: U32, +hash: U32) -> Gen<G>:
  Gen{T.Leaf{Ind{gene, fit, hash}}, fit, gene, hash}

# População inicial aleatória de 2^d indivíduos, em paralelo
def first_gen(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
              d: Nat, +ctx: P, +seed: U32) -> Gen<G>:
  match d:
    case 0n:
      +g = init(ctx, seed)
      leaf_gen(G, g, fit(ctx, g), 0)
    case 1n+ +p:
      l r = first_gen(~P, ~G, ~init, ~fit, p, ctx, R.split.fst(seed)) first_gen(~P, ~G, ~init, ~fit, p, ctx, R.split.snd(seed))
      merge_gen(G, l, r)

# ----------------------------------------------------------------
# SELEÇÃO POR TORNEIO (tournament_selection)
# ----------------------------------------------------------------
# Como no Rust, o torneio trabalha com ÍNDICES: sorteia `ts` índices, lê a
# aptidão de cada um e fica com o melhor (empates com o primeiro sorteado,
# `fitness > best_fit`). O segundo pai exclui o índice do primeiro
# (random_range_except) e, quando os hashes são conhecidos (diversity_check),
# todo candidato com o MESMO hash do primeiro: um clone dele daria um
# cruzamento inútil. O candidato excluído não conta (o `continue` do Rust); se
# todos forem excluídos, o pai sai de um sorteio que só exclui o índice (o
# Rust varre a população atrás de um hash diferente; com diversity_check a
# população quase não tem repetidos e o caso é raro).
#
# ONDE os torneios leem a população importa muito. A população é um valor
# `+` compartilhado pelas tarefas da reprodução, e abrir um nó compartilhado
# mexe nas contagens de referência dos campos: medido no nativo, descer a
# árvore custa ~25 ns por nível, ~170 ns por sorteio numa ilha de 64 — mesmo
# com tudo na cache. Por isso a seleção é uma passada SEQUENCIAL por ilha,
# antes da reprodução: um retrato da população (aptidão e hash de cada
# índice) vai para um `Array` local, onde um sorteio custa ~3 ns, e sai dali a
# lista dos índices dos pais, dois por par. A reprodução paralela desce a
# árvore só para buscar os DOIS genomas de cada par.

def is_odd(+x: U32) -> Bool:
  Bool.not(U32.is_even(x))

# A população é uma árvore perfeita de N = 2^d folhas: o indivíduo de índice
# `i` é achado descendo d níveis, um bit de `i` por nível (do menos
# significativo). `go_right` é o bit do nível atual, calculado no passo
# anterior (match não escrutina valor computado).
def sample.go(-G: Data, t: T.PopTree<Ind<G>>, go_right: Bool, +bits: U32) -> Ind<G>:
  match t go_right:
    case T.Leaf{ind} _:
      ind
    case T.Node{left, right} True{}:
      +rest = U32.shrn(bits, 1n)
      sample.go(G, right, is_odd(rest), rest)
    case T.Node{left, right} False{}:
      +rest = U32.shrn(bits, 1n)
      sample.go(G, left, is_odd(rest), rest)

# O indivíduo de índice `idx`
def sample_at(-G: Data, t: T.PopTree<Ind<G>>, +idx: U32) -> Ind<G>:
  sample.go(G, t, is_odd(idx), idx)

# Retrato da população: a aptidão do índice i na posição 2i do Array, o hash
# em 2i+1. O índice de uma folha é o caminho até ela lido a partir do bit
# menos significativo (o mesmo de `sample_at`): descer à direita no nível de
# passo `step` soma `step`.
def snapshot.go(-G: Data, t: T.PopTree<Ind<G>>, a: Array<U32>, +idx: U32, +step: U32) -> Array<U32>:
  match t:
    case T.Leaf{ind}:
      Ind{_, f, h} = ind
      +at = U32.shln(idx, 1n)
      Array.set(U32, Array.set(U32, a, at, f), U32.inc(at), h)
    case T.Node{left, right}:
      +s2 = U32.shln(step, 1n)
      snapshot.go(G, right, snapshot.go(G, left, a, idx, s2), (idx + step : U32), s2)

# Todos os torneios de uma geração num laço só. O Array é afim e o retorno de
# uma chamada não pode ser desestruturado, então não dá para ter uma função
# "torneio" que devolva o índice E o Array: cada passo lê UM valor e as
# decisões descem como parâmetros.
#   r          o Array e o valor pedido no passo anterior: a aptidão do
#              candidato `c` (fase `on_fit`) ou o seu hash
#   fin, w     um torneio terminou no passo anterior: emitir o vencedor `w`
#              (`emit`, aplicado ao resultado da recursão)
#   stop       não há mais torneios (emitir `w` e parar)
#   left       candidatos que faltam no torneio atual
#   bi bf bh   o melhor até agora (bi >= n: nenhum, o `None` do Rust)
#   ex xh      índice e hash excluídos (ex >= n e xh = 0: nenhum)
#   second     o torneio atual é o do segundo pai
#   pairs      pares que faltam, contando o atual
def emit(fin: Bool, +w: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match fin:
    case True{}:
      Con{w, rest}
    case False{}:
      rest

def select.go(k: Nat, r: Array<U32> & U32, on_fit: Bool, stop: Bool, +fin: Bool,
              +w: U32, +c: U32, +cf: U32, +left: U32, +bi: U32, +bf: U32, +bh: U32,
              +ex: U32, +xh: U32, +second: Bool, +pairs: U32, +n: U32, +ts: U32,
              +seed: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      (a, +v) = r
      match on_fit stop:
        case _ True{}:
          emit(fin, w, Nil{})
        case True{} False{}:
          emit(fin, w, select.go(p, Array.get(U32, a, U32.inc(U32.shln(c, 1n))), False{}, False{}, False{},
                                 w, c, v, left, bi, bf, bh, ex, xh, second, pairs, n, ts, seed))
        case False{} False{}:
          # o candidato `c`, de aptidão `cf` e hash `v`
          +skip = Bool.and(Bool.not(U32.is_zero(xh)), U32.is_eq(v, xh))
          +better = Bool.and(Bool.not(skip), Bool.or(U32.is_ge(bi, n), U32.is_gt(cf, bf)))
          +bi2 = pick_fit(better, c, bi)
          +bh2 = pick_fit(better, v, bh)
          +left2 = (left - 1 : U32)
          +done = U32.is_zero(left2)
          # se o torneio acabou: o vencedor, e o próximo torneio — o do segundo
          # pai (exclui o vencedor e o seu hash) ou o primeiro do próximo par
          +w2 = Bool.pick(U32, U32.is_ge(bi2, n), R.range_except(R.split.fst(seed), n, ex), bi2)
          +pairs2 = Bool.pick(U32, second, (pairs - 1 : U32), pairs)
          +nex = Bool.pick(U32, done, Bool.pick(U32, second, n, w2), ex)
          +nxh = Bool.pick(U32, done, Bool.pick(U32, second, 0, bh2), xh)
          +nc = R.range_except(seed, n, nex)
          select.go(p, Array.get(U32, a, U32.shln(nc, 1n)), True{},
                    Bool.and(done, Bool.and(second, U32.is_zero(pairs2))), done,
                    Bool.pick(U32, done, w2, w), nc, 0, Bool.pick(U32, done, ts, left2),
                    Bool.pick(U32, done, n, bi2), Bool.pick(U32, done, 0, pick_fit(better, cf, bf)),
                    Bool.pick(U32, done, 0, bh2), nex, nxh,
                    Bool.pick(Bool, done, Bool.not(second), second), Bool.pick(U32, done, pairs2, pairs),
                    n, ts, R.step(seed))

# Os índices dos pais de `pairs` pares, em ordem: [a0, b0, a1, b1, ...], com
# torneios de `ts` sorteios entre os N = 2^d indivíduos de `pop`
def select(-G: Data, +pop: T.PopTree<Ind<G>>, +d: Nat, +pairs: U32, +ts: U32, +seed: U32) -> List<&2, U32>:
  +n = U32.shln(1, d)
  +c = R.range_except(seed, n, n)
  select.go(U32.to_nat((U32.shln((pairs * ts : U32), 2n) + 4 : U32)),
            Array.get(U32, snapshot.go(G, pop, Array.new(U32, Nat.add(d, 1n), 0), 0, 1), U32.shln(c, 1n)),
            True{}, False{}, False{}, 0, c, 0, ts, n, 0, 0, n, 0, False{}, pairs, n, ts, R.step(seed))

# ----------------------------------------------------------------
# REPRODUÇÃO (run_generation)
# ----------------------------------------------------------------

# Taxas efetivas de UMA geração, já com os multiplicadores de estagnação
type Eff is Data:
  Eff{tsize: Nat, cross_rate: U32, mut_rate: U32, gene_rate: U32, npop: U32}

def Eff.tsize(e: Eff) -> U32:
  Eff{t, _, _, _, _} = e
  U32.from_nat(t)

def Eff.gene_rate(e: Eff) -> U32:
  Eff{_, _, _, g, _} = e
  g

# Dois pais, dois filhos, como o `crossover(child_a, child_b, parent_a,
# parent_b)` do Rust; sem cruzamento, os filhos são cópias dos dois pais
def cross_maybe(~P: Data, ~G: Data, ~cross: P -> G -> G -> U32 -> G & G,
                hit: Bool, +ctx: P, p1: G, p2: G, +seed: U32) -> G & G:
  match hit:
    case True{}:
      cross(ctx, p1, p2, seed)
    case False{}:
      (p1, p2)

def mutate_maybe(~P: Data, ~G: Data, ~mutate: P -> G -> U32 -> U32 -> G,
                 hit: Bool, +ctx: P, g: G, +rate: U32, +seed: U32) -> G:
  match hit:
    case True{}:
      mutate(ctx, g, rate, seed)
    case False{}:
      g

# O hash guardado de um genoma: nunca 0
def hash_of(~P: Data, ~G: Data, ~hash: P -> G -> U32, +ctx: P, g: G) -> U32:
  U32.max(R.mix(hash(ctx, g)), 1)

# O hash de um filho recém-criado, se há diversity_check (0 = desconhecido)
def hash_maybe(~P: Data, ~G: Data, ~hash: P -> G -> U32, on: Bool, +ctx: P, g: G) -> U32:
  match on:
    case True{}:
      hash_of(~P, ~G, ~hash, ctx, g)
    case False{}:
      0

# Um filho pronto: mutado com a chance `mr` (cada filho tem o seu sorteio,
# como no Rust), avaliado e, com diversity_check (`hon`), hasheado — como o
# Rust, que calcula o hash ao criar o filho. Aqui isso também tira o hash da
# passada `dedup`, que é sequencial por ilha, e o põe na reprodução, que é
# paralela. `m` é a semente deste filho: o sorteio usa `m` e a mutação um
# fluxo derivado dele (sem sobrepor o do cruzamento).
def child_leaf(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
               ~mutate: P -> G -> U32 -> U32 -> G,
               +ctx: P, +hon: Bool, g: G, +mr: U32, +gr: U32, +m: U32) -> Gen<G>:
  +c = mutate_maybe(~P, ~G, ~mutate, R.hit(m, mr), ctx, g, gr, R.split.fst(m))
  leaf_gen(G, c, fit(ctx, c), hash_maybe(~P, ~G, ~hash, hon, ctx, c))

# Os dois filhos de um cruzamento viram duas folhas vizinhas. O par chega
# como PARÂMETRO: desestruturar o retorno de uma chamada é proibido.
def pair_leaves(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
                ~mutate: P -> G -> U32 -> U32 -> G,
                kids: G & G, +ctx: P, +hon: Bool, +mr: U32, +gr: U32, +m: U32) -> Gen<G>:
  (ka, kb) = kids
  merge_gen(G, child_leaf(~P, ~G, ~fit, ~hash, ~mutate, ctx, hon, ka, mr, gr, R.split.snd(m)),
               child_leaf(~P, ~G, ~fit, ~hash, ~mutate, ctx, hon, kb, mr, gr, R.split.trd(m)))

# Um par de folhas da nova geração. `sel` traz os índices dos dois pais,
# escolhidos por torneio (`select`). O par mais à esquerda (`on_elite`) é o
# `offspring[0]` e o resto ímpar do Rust: o campeão intacto (elitismo
# estrito) e um filho de um pai só, clonado e talvez mutado.
def breed_pair(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
               ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
               on_elite: Bool, +sel: List<&2, U32>, +ctx: P, +hon: Bool, +seed: U32,
               +champ_f: U32, +champ_g: G, +champ_h: U32, +pop: T.PopTree<Ind<G>>, +eff: Eff) -> Gen<G>:
  match on_elite:
    case True{}:
      Eff{_, _, mr, gr, _} = eff
      p1 = Ind.gene(G, sample_at(G, pop, V.nth(U32, sel, 0, 0)))
      merge_gen(G, leaf_gen(G, champ_g, champ_f, champ_h),
                   child_leaf(~P, ~G, ~fit, ~hash, ~mutate, ctx, hon, p1, mr, gr, R.split.trd(seed)))
    case False{}:
      Eff{_, cr, mr, gr, _} = eff
      p1 = Ind.gene(G, sample_at(G, pop, V.nth(U32, sel, 0, 0)))
      p2 = Ind.gene(G, sample_at(G, pop, V.nth(U32, sel, 1, 0)))
      pair_leaves(~P, ~G, ~fit, ~hash, ~mutate,
                  cross_maybe(~P, ~G, ~cross, R.hit(seed, cr), ctx, p1, p2, R.split.fth(seed)),
                  ctx, hon, mr, gr, R.split.trd(seed))

# Gera a próxima população, de 2^(k+1) indivíduos: `k` níveis de árvore
# acima dos pares; `sel` tem os 2^(k+1) índices de pais, dois por par, e cada
# metade leva a sua metade. As duas metades são uma CHAMADA PARALELA: sem
# ela, tudo roda num núcleo só.
def breed(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
          ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
          k: Nat, on_elite: Bool, +sel: List<&2, U32>, +ctx: P, +hon: Bool, +seed: U32,
          +champ_f: U32, +champ_g: G, +champ_h: U32, +pop: T.PopTree<Ind<G>>, +eff: Eff) -> Gen<G>:
  match k:
    case 0n:
      breed_pair(~P, ~G, ~fit, ~hash, ~cross, ~mutate, on_elite, sel, ctx, hon, seed, champ_f, champ_g, champ_h, pop, eff)
    case 1n+ +p:
      +half = U32.shln(2, p)
      gl gr = breed(~P, ~G, ~fit, ~hash, ~cross, ~mutate, p, on_elite, V.take(U32, sel, half), ctx, hon, R.split.fst(seed), champ_f, champ_g, champ_h, pop, eff) breed(~P, ~G, ~fit, ~hash, ~cross, ~mutate, p, False{}, V.drop(U32, sel, half), ctx, hon, R.split.snd(seed), champ_f, champ_g, champ_h, pop, eff)
      merge_gen(G, gl, gr)

# Uma geração de 2^d indivíduos (com d = 0, só o campeão): primeiro a
# seleção, sequencial, depois a reprodução, paralela
def breed_top(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
              ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
              d: Nat, +ctx: P, +hon: Bool, +seed: U32, +champ_f: U32, +champ_g: G, +champ_h: U32,
              +pop: T.PopTree<Ind<G>>, +eff: Eff) -> Gen<G>:
  match d:
    case 0n:
      leaf_gen(G, champ_g, champ_f, champ_h)
    case 1n+ +p:
      +sel = select(G, pop, Nat.add(p, 1n), U32.shln(1, p), Eff.tsize(eff), R.split.snd(seed))
      breed(~P, ~G, ~fit, ~hash, ~cross, ~mutate, p, True{}, sel, ctx, hon, R.split.fst(seed), champ_f, champ_g, champ_h, pop, eff)

def next_gen(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
             ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
             gen: Gen<G>, d: Nat, +ctx: P, +hon: Bool, +eff: Eff, +seed: U32) -> Gen<G>:
  match gen:
    case Gen{+tree, cf, cg, ch}:
      breed_top(~P, ~G, ~fit, ~hash, ~cross, ~mutate, d, ctx, hon, seed, cf, cg, ch, tree, eff)

# ----------------------------------------------------------------
# DIVERSIDADE (diversity_check)
# ----------------------------------------------------------------
# No Rust, ao criar um filho cujo hash já existe na nova geração, o motor
# tenta outros pais (até 3 vezes) e, se ainda repetir, muta de novo. Lá há um
# `HashSet` compartilhado sendo escrito durante a reprodução — o que tarefas
# paralelas não podem ter.
#
# Aqui a verificação é uma passada DEPOIS da reprodução, sequencial dentro da
# ilha (as ilhas continuam em paralelo): a população é percorrida na ordem das
# folhas, cada hash é marcado num conjunto de bits num `Array` local, e quem
# repetir um hash já visto é mutado de novo (com 4x a taxa por gene, para
# compensar a falta das novas tentativas com outros pais) e re-hasheado, e é
# o hash NOVO que é marcado, como no Rust. O elite é o primeiro da ordem,
# então nunca é tocado.
#
# Os filhos já chegam com o hash, calculado na reprodução paralela
# (`child_leaf`), e o elite traz o seu: aqui só é calculado o de quem ainda
# não tem (hash 0) — um migrante ou o melhor reintroduzido. Os hashes
# guardados nunca são 0 (0 é "desconhecido").
#
# O conjunto tem 2^16 bits: uma colisão entre hashes diferentes (chance
# ~N/65536) só causa uma mutação a mais — inofensiva.

def flatten(-G: Data, t: T.PopTree<Ind<G>>) -> List<&2, Ind<G>>:
  match t:
    case T.Leaf{ind}:
      Con{ind, Nil{}}
    case T.Node{left, right}:
      l r = flatten(G, left) flatten(G, right)
      List.append(&2, Ind<G>, l, r)

def first_ind(-G: Data, l: List<&2, Ind<G>>, dflt: Ind<G>) -> Ind<G>:
  match l:
    case Nil{}:
      dflt
    case Con{h, t}:
      h

def leaf_of(-G: Data, ind: Ind<G>) -> Gen<G>:
  Ind{+g, +f, +h} = ind
  leaf_gen(G, g, f, h)

# Reconstrói uma geração de 2^d indivíduos a partir da lista em ordem,
# recalculando o campeão
def rebuild(-G: Data, d: Nat, +l: List<&2, Ind<G>>, +dflt: Ind<G>) -> Gen<G>:
  match d:
    case 0n:
      leaf_of(G, first_ind(G, l, dflt))
    case 1n+ +p:
      +half = U32.shln(1, p)
      gl gr = rebuild(G, p, V.take(Ind<G>, l, half), dflt) rebuild(G, p, V.drop(Ind<G>, l, half), dflt)
      merge_gen(G, gl, gr)

def word_of(+h: U32) -> U32:
  U32.shrn(U32.and(h, 65535), 5n)

def bit_in(+h: U32) -> U32:
  U32.shln(1, U32.to_nat(U32.and(h, 31)))

def fill_hash.go(~P: Data, ~G: Data, ~hash: P -> G -> U32,
                 missing: Bool, +ctx: P, +g: G, f: U32, h: U32) -> Ind<G>:
  match missing:
    case True{}:
      Ind{g, f, hash_of(~P, ~G, ~hash, ctx, g)}
    case False{}:
      Ind{g, f, h}

# Calcula o hash só se ainda não for conhecido
def fill_hash(~P: Data, ~G: Data, ~hash: P -> G -> U32, +ctx: P, ind: Ind<G>) -> Ind<G>:
  Ind{g, f, +h} = ind
  fill_hash.go(~P, ~G, ~hash, U32.is_zero(h), ctx, g, f, h)

# Marca o hash `h` no conjunto (o par lido é o estado, Armadilha 3b)
def mark.go(r: Array<U32> & U32, +h: U32) -> Array<U32>:
  (a, w) = r
  Array.set(U32, a, word_of(h), U32.or(w, bit_in(h)))

def mark(a: Array<U32>, +h: U32) -> Array<U32>:
  mark.go(Array.get(U32, a, word_of(h)), h)

def remutate(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~mutate: P -> G -> U32 -> U32 -> G,
             ~hash: P -> G -> U32, dup: Bool, ind: Ind<G>, +ctx: P, +rate: U32, +seed: U32) -> Ind<G>:
  match dup:
    case True{}:
      +g = mutate(ctx, Ind.gene(G, ind), rate, seed)
      Ind{g, fit(ctx, g), hash_of(~P, ~G, ~hash, ctx, g)}
    case False{}:
      ind

# `r` traz o conjunto e a palavra onde mora o bit do hash de `prev` (lida
# ANTES de marcá-lo). Neste passo `prev` é resolvido (remutado se repetido) e
# o hash com que ele FICOU é marcado; só então o próximo é lido.
def dedup.go(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~mutate: P -> G -> U32 -> U32 -> G,
             ~hash: P -> G -> U32,
             inds: List<&2, Ind<G>>, r: Array<U32> & U32, +prev: Ind<G>,
             +ctx: P, +rate: U32, +seed: U32) -> List<&2, Ind<G>>:
  match inds:
    case Nil{}:
      (a, w) = r
      +dup = Bool.not(U32.is_zero(U32.and(w, bit_in(Ind.hash(G, prev)))))
      Con{remutate(~P, ~G, ~fit, ~mutate, ~hash, dup, prev, ctx, rate, seed), Nil{}}
    case Con{x, t}:
      (a, w) = r
      +dup = Bool.not(U32.is_zero(U32.and(w, bit_in(Ind.hash(G, prev)))))
      +cur = remutate(~P, ~G, ~fit, ~mutate, ~hash, dup, prev, ctx, rate, seed)
      +nx = fill_hash(~P, ~G, ~hash, ctx, x)
      Con{cur, dedup.go(~P, ~G, ~fit, ~mutate, ~hash, t, Array.get(U32, mark(a, Ind.hash(G, cur)), word_of(Ind.hash(G, nx))),
                        nx, ctx, rate, R.step(seed))}

def dedup(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~mutate: P -> G -> U32 -> U32 -> G,
          ~hash: P -> G -> U32, inds: List<&2, Ind<G>>, +ctx: P, +rate: U32, +seed: U32) -> List<&2, Ind<G>>:
  match inds:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      +nx = fill_hash(~P, ~G, ~hash, ctx, x)
      dedup.go(~P, ~G, ~fit, ~mutate, ~hash, t, Array.get(U32, Array.new(U32, 11n, 0), word_of(Ind.hash(G, nx))), nx, ctx, rate, seed)

def diversify(~P: Data, ~G: Data, ~fit: P -> G -> U32, ~mutate: P -> G -> U32 -> U32 -> G,
              ~hash: P -> G -> U32, on: Bool, gen: Gen<G>, +d: Nat,
              +ctx: P, +rate: U32, +seed: U32) -> Gen<G>:
  match on:
    case False{}:
      gen
    case True{}:
      Gen{pop, bf, bg, bh} = gen
      rebuild(G, d, dedup(~P, ~G, ~fit, ~mutate, ~hash, flatten(G, pop), ctx, rate, seed), Ind{bg, bf, bh})

# ----------------------------------------------------------------
# INJEÇÃO (reintrodução do melhor e migração)
# ----------------------------------------------------------------

def replace_at.go(-G: Data, t: T.PopTree<Ind<G>>, go_right: Bool, +bits: U32, ind: Ind<G>) -> T.PopTree<Ind<G>>:
  match t go_right:
    case T.Leaf{_} _:
      T.Leaf{ind}
    case T.Node{left, right} True{}:
      +rest = U32.shrn(bits, 1n)
      T.Node{left, replace_at.go(G, right, is_odd(rest), rest, ind)}
    case T.Node{left, right} False{}:
      +rest = U32.shrn(bits, 1n)
      T.Node{replace_at.go(G, left, is_odd(rest), rest, ind), right}

# Põe `m` na folha de índice `idx`; se ele for melhor, também vira o campeão
# (e portanto o elite da próxima geração)
def inject(-G: Data, gen: Gen<G>, +m: Ind<G>, +idx: U32) -> Gen<G>:
  match gen:
    case Gen{p, +cf, cg, ch}:
      Ind{mg, +mf, +mh} = m
      +better = U32.is_gt(mf, cf)
      Gen{replace_at.go(G, p, is_odd(idx), idx, Ind{mg, mf, mh}), pick_fit(better, mf, cf), pick_gene(G, better, mg, cg), pick_fit(better, mh, ch)}

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
  fresh_ind(G, bg, bf)

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
# Controle de estagnação adaptativo, como no Rust: depois de max_stag/2
# gerações sem melhora, a mutação cresce até 2x (e além) e o torneio encolhe
# até 2, para tentar escapar do platô.
def effective(+cfg: Config, +stagnated: U32) -> Eff:
  Config{cr, mr, gr, ts, ms, _, pd, _} = cfg
  +half = U32.max(U32.div(ms, 2), 1)
  +excess = Bool.pick(U32, Bool.or(U32.is_zero(ms), U32.is_le(stagnated, half)), 0, (stagnated - half : U32))
  +ratio = (U32.to_f32(excess) / U32.to_f32(half) : F32)
  +mult = ({1.0 : F32} + ratio : F32)
  +tmult = ({1.0 : F32} - F32.min(ratio, {1.0 : F32}) : F32)
  +tsize = U32.max(F32.to_u32((U32.to_f32(ts) * tmult : F32)), 2)
  Eff{U32.to_nat(tsize), cr, R.scale(mr, mult), R.scale(gr, mult), U32.shln(1, U32.to_nat(pd))}

# Depois de uma geração sem melhora. `reset` = passou de max_stag gerações:
# reinicia a população (o melhor já encontrado continua guardado);
# `reintro` = exatamente max_stag/2: reintroduz o melhor numa posição
# aleatória da população, como no Rust.
def stagnate(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
             reset: Bool, reintro: Bool, gen: Gen<G>, +ctx: P, +cfg: Config,
             +bf: U32, +bg: G, +ss: U32, +sf: U32, +g: U32, +seed: U32) -> Island<G>:
  match reset reintro:
    case True{} _:
      Island{first_gen(~P, ~G, ~init, ~fit, Config.pop_d(cfg), ctx, seed), bf, bg, g, 0, U32.inc(g)}
    case False{} True{}:
      Island{inject(G, gen, fresh_ind(G, bg, bf), R.mix(seed)), bf, bg, ss, sf, U32.inc(g)}
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
def island_step(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
                ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
                isl: Island<G>, +ctx: P, +cfg: Config, +seed: U32) -> Island<G>:
  match isl:
    case Island{gen, +bf, bg, +ss, +sf, +g}:
      +eff = effective(cfg, (g - ss : U32))
      +gen1 = next_gen(~P, ~G, ~fit, ~hash, ~cross, ~mutate, gen, Config.pop_d(cfg), ctx, Config.diversity(cfg), eff, seed)
      +gen2 = diversify(~P, ~G, ~fit, ~mutate, ~hash, Config.diversity(cfg), gen1, Config.pop_d(cfg),
                        ctx, R.scale(Eff.gene_rate(eff), {4.0 : F32}), R.split.fth(seed))
      +cur = Gen.bfit(G, gen2)
      +better = U32.is_gt(cur, bf)
      after_gen(~P, ~G, ~init, ~fit, U32.is_gt(cur, sf), gen2, ctx, cfg, cur,
                pick_fit(better, cur, bf), pick_gene(G, better, Gen.bgene(G, gen2), bg),
                ss, sf, g, R.split.trd(seed))

# Encerra quando o melhor atinge a aptidão máxima configurada
def is_done(-G: Data, +cfg: Config, +isl: Island<G>) -> Bool:
  +mf = Config.max_fit(cfg)
  Bool.and(Bool.not(U32.is_zero(mf)), U32.is_ge(Island.best_f(G, isl), mf))

def island_loop(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
                ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
                k: Nat, isl: Island<G>, done: Bool, +ctx: P, +cfg: Config, +seed: U32) -> Island<G>:
  match k done:
    case _ True{}:
      isl
    case 0n False{}:
      isl
    case 1n+p False{}:
      +isl2 = island_step(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, isl, ctx, cfg, seed)
      island_loop(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, p, isl2, is_done(G, cfg, isl2), ctx, cfg, R.split.fth(seed))

# Uma população nova, aleatória
def new_island(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32,
               +ctx: P, +cfg: Config, +seed: U32) -> Island<G>:
  island(G, first_gen(~P, ~G, ~init, ~fit, Config.pop_d(cfg), ctx, seed))

# Evolui uma população isolada por até `k` gerações
def run_island(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
               ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
               k: Nat, +isl: Island<G>, +ctx: P, +cfg: Config, +seed: U32) -> Island<G>:
  island_loop(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, k, isl, is_done(G, cfg, isl), ctx, cfg, seed)

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
def evolve_archipelago(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
                       ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
                       arch: ArchTree<G>, +e: Nat, +ctx: P, +cfg: Config, +seed: U32) -> ArchTree<G>:
  match arch:
    case SingleIsland{isl}:
      SingleIsland{run_island(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, e, isl, ctx, cfg, seed)}
    case ArchBranch{left, right}:
      l r = evolve_archipelago(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, left, e, ctx, cfg, R.split.fst(seed)) evolve_archipelago(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, right, e, ctx, cfg, R.split.snd(seed))
      ArchBranch{l, r}

# ----------------------------------------------------------------
# MIGRAÇÃO EM ANEL
# ----------------------------------------------------------------
# Cada ilha recebe o melhor da ilha ANTERIOR no anel (a ilha 0 recebe o da
# última). O migrante é INJETADO num indivíduo comum (a última folha da
# população), sem tomar o slot de elite: a ilha mantém sua própria linhagem.
# Uma boa solução percorre o anel em k épocas em vez de ocupar todas as ilhas
# de uma vez — que era o que fazia as ilhas convergirem para o mesmo mínimo
# local.

# Os melhores de cada ilha, na ordem das folhas
def island_bests(-G: Data, arch: ArchTree<G>) -> List<&2, Ind<G>>:
  match arch:
    case SingleIsland{isl}:
      Con{Island.best(G, isl), Nil{}}
    case ArchBranch{left, right}:
      l r = island_bests(G, left) island_bests(G, right)
      List.append(&2, Ind<G>, l, r)

def nth_ind(-G: Data, l: List<&2, Ind<G>>, k: Nat, dflt: Ind<G>) -> Ind<G>:
  match l k:
    case Nil{} 0n:
      dflt
    case Nil{} 1n+p:
      dflt
    case Con{h, t} 0n:
      h
    case Con{h, t} 1n+p:
      nth_ind(G, t, p, dflt)

def migrate_ring(-G: Data, arch: ArchTree<G>, +bests: List<&2, Ind<G>>,
                 +k: U32, +i: U32, +size: U32) -> ArchTree<G>:
  match arch:
    case SingleIsland{isl}:
      Island{gen, +bf, +bg, ss, sf, g} = isl
      +m = nth_ind(G, bests, U32.to_nat(U32.mod((i + k - 1 : U32), k)), fresh_ind(G, bg, bf))
      +better = U32.is_gt(Ind.fit(G, m), bf)
      SingleIsland{Island{inject(G, gen, m, R.MAX()), pick_fit(better, Ind.fit(G, m), bf),
                          pick_gene(G, better, Ind.gene(G, m), bg), ss, sf, g}}
    case ArchBranch{left, right}:
      +half = U32.shrn(size, 1n)
      l r = migrate_ring(G, left, bests, k, i, half) migrate_ring(G, right, bests, k, (i + half : U32), half)
      ArchBranch{l, r}

def migrate(-G: Data, +arch: ArchTree<G>) -> ArchTree<G>:
  +k = U32.from_nat(arch_island_count(G, arch))
  migrate_ring(G, arch, island_bests(G, arch), k, 0, k)

def arch_done(-G: Data, +cfg: Config, +arch: ArchTree<G>) -> Bool:
  +mf = Config.max_fit(cfg)
  Bool.and(Bool.not(U32.is_zero(mf)), U32.is_ge(Ind.fit(G, best_archipelago(G, arch)), mf))

def run_archipelago.go(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
                       ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
                       epochs: Nat, arch: ArchTree<G>, done: Bool, +e: Nat, +ctx: P, +cfg: Config,
                       +seed: U32) -> ArchTree<G>:
  match epochs done:
    case _ True{}:
      arch
    case 0n False{}:
      arch
    case 1n+p False{}:
      +evolved = evolve_archipelago(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, arch, e, ctx, cfg, seed)
      +migrated = migrate(G, evolved)
      run_archipelago.go(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, p, migrated, arch_done(G, cfg, migrated), e, ctx, cfg, R.split.trd(seed))

# `epochs` épocas de `e` gerações por ilha, com migração em anel entre
# épocas; para cedo se atingir a aptidão máxima
def run_archipelago(~P: Data, ~G: Data, ~init: P -> U32 -> G, ~fit: P -> G -> U32, ~hash: P -> G -> U32,
                    ~cross: P -> G -> G -> U32 -> G & G, ~mutate: P -> G -> U32 -> U32 -> G,
                    epochs: Nat, +arch: ArchTree<G>, +e: Nat, +ctx: P, +cfg: Config,
                    +seed: U32) -> ArchTree<G>:
  run_archipelago.go(~P, ~G, ~init, ~fit, ~hash, ~cross, ~mutate, epochs, arch, arch_done(G, cfg, arch), e, ctx, cfg, seed)
