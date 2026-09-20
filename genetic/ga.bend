import Base
import ./arena.bend as A
import ./../utils/arrays.bend as Arr
import ./../utils/tuples.bend as T
import ./../utils/random.bend as R

# ================================================================
# O MOTOR (ga.bend)
# ================================================================
# Uma geração são `size/2` EVENTOS de reprodução. Cada evento:
#
#   1. sorteia duas vítimas distintas pelo torneio do PIOR entre `tsize`,
#      nunca o elite (que é excluído do sorteio: elitismo estrito de graça)
#   2. sorteia dois pais pelo torneio do MELHOR entre `tsize`
#   3. copia os genes dos pais para as vítimas, que viram os filhos
#   4. com probabilidade `cross_rate`, cruza os dois filhos entre si
#   5. com probabilidade `mut_rate`, muta cada filho (taxa por gene
#      `gene_rate`), e o AVALIA na hora
#
# Por que avaliar na hora: um filho recém-nascido tem fitness 0 (a marca de
# "não avaliado") e o torneio do pior escolheria logo ele como vítima do
# evento seguinte — o filho morreria antes de viver. Avaliando na hora o custo
# é o mesmo (uma avaliação por filho) e o problema some.
#
# Por que steady-state, e não "monta a geração nova a partir da velha": a
# geração nova exigiria um segundo arranjo (2× memória). Aqui os filhos nascem
# por cima dos piores, no mesmo arranjo. O efeito é pressão seletiva um pouco
# maior; a etapa 4 do PLAN.md manda comparar a convergência com o motor v2.
#
# NADA aqui aloca: tudo é `Array.swap` sobre a arena.
# ================================================================

type Config is Data:
  Config{cross_rate: U32, mut_rate: U32, gene_rate: U32, tsize: U32, diversity: Bool, max_stag: U32}

# `max_stag` = gerações sem melhora até reiniciar a população (0 desliga o
# controle de estagnação). Na metade disso a mutação já dobra.
def cfg_new(+cross_rate: U32, +mut_rate: U32, +gene_rate: U32, +tsize: U32,
            +diversity: Bool, +max_stag: U32) -> Config:
  Config{cross_rate, mut_rate, gene_rate, tsize, diversity, max_stag}

def cfg_cross(+cfg: Config) -> U32:
  match cfg:
    case Config{+cross_rate, mut_rate, gene_rate, tsize, diversity, max_stag}:
      cross_rate

def cfg_mut(+cfg: Config) -> U32:
  match cfg:
    case Config{cross_rate, +mut_rate, gene_rate, tsize, diversity, max_stag}:
      mut_rate

def cfg_gene(+cfg: Config) -> U32:
  match cfg:
    case Config{cross_rate, mut_rate, +gene_rate, tsize, diversity, max_stag}:
      gene_rate

# com `diversity = False{}` o motor NÃO calcula o hash dos filhos nem faz a
# passada de diversidade. Medido no OneMax (4096 genes, pop 256, 200 gerações):
# ligado custa 2× o tempo (o hash é mais uma passada pelo genoma) e dá ~2% de
# aptidão. Vale para problema que converge para clones (o sudoku do v2), não
# para OneMax.
def cfg_div(+cfg: Config) -> Bool:
  match cfg:
    case Config{cross_rate, mut_rate, gene_rate, tsize, +diversity, max_stag}:
      diversity

def cfg_stag(+cfg: Config) -> U32:
  match cfg:
    case Config{cross_rate, mut_rate, gene_rate, tsize, diversity, +max_stag}:
      max_stag

def cfg_tsize(+cfg: Config) -> U32:
  match cfg:
    case Config{cross_rate, mut_rate, gene_rate, +tsize, diversity, max_stag}:
      tsize

# O que uma callback precisa saber. `Data`, porque as callbacks recebem com `+`.
type Call<-P: Data> is Data:
  Call{ctx: P, rate: U32, gene_rate: U32, seed: U32, hash_on: Bool, cross_on: Bool}

def call_ctx(-P: Data, +c: Call<P>) -> P:
  match c:
    case Call{+ctx, rate, gene_rate, seed, hash_on, cross_on}:
      ctx

def call_rate(-P: Data, +c: Call<P>) -> U32:
  match c:
    case Call{ctx, +rate, gene_rate, seed, hash_on, cross_on}:
      rate

# a taxa POR GENE viaja no record, e não como argumento template: template só
# aceita argumento comptime, e isto vem da Config em tempo de execução
def call_gene(-P: Data, +c: Call<P>) -> U32:
  match c:
    case Call{ctx, rate, +gene_rate, seed, hash_on, cross_on}:
      gene_rate

def call_seed(-P: Data, +c: Call<P>) -> U32:
  match c:
    case Call{ctx, rate, gene_rate, +seed, hash_on, cross_on}:
      seed

def call_cross_on(-P: Data, +c: Call<P>) -> Bool:
  match c:
    case Call{ctx, rate, gene_rate, seed, hash_on, +cross_on}:
      cross_on

def call_hash_on(-P: Data, +c: Call<P>) -> Bool:
  match c:
    case Call{ctx, rate, gene_rate, seed, +hash_on, cross_on}:
      hash_on

# O estado de uma corrida.
type Run<-G: Type> is Type:
  Run{pop: A.Pop<G>, best_idx: U32, best_fit: U32, stag: U32, seed: U32}

# ----------------------------------------------------------------
# SORTEIO COM DUAS EXCLUSÕES
# ----------------------------------------------------------------
# Uniforme em [0, n) pulando `ex1` e `ex2` (um valor >= n significa "não
# exclui"). Sem viés: sorteia no intervalo encurtado e desloca.

def draw.shift(+c: U32, +a: U32, +b: U32) -> U32:
  +c1 = Bool.pick(U32, U32.is_ge(c, a), U32.inc(c), c)
  Bool.pick(U32, U32.is_ge(c1, b), U32.inc(c1), c1)

def draw(+seed: U32, +n: U32, +ex1: U32, +ex2: U32) -> U32:
  +a = U32.min(ex1, ex2)
  +b = U32.max(ex1, ex2)
  +tem_a = Bool.to_u32(U32.is_lt(a, n))
  +tem_b = Bool.to_u32(Bool.and(U32.is_lt(b, n), U32.is_ne(a, b)))
  +livre = U32.max((n - (tem_a + tem_b : U32) : U32), 1)
  draw.shift(R.range(seed, livre), Bool.pick(U32, U32.is_zero(tem_a), n, a),
             Bool.pick(U32, U32.is_zero(tem_b), n, b))

# ----------------------------------------------------------------
# TORNEIO
# ----------------------------------------------------------------
# `worst = True{}` procura o PIOR (escolha de vítima); `False{}`, o melhor.
# Cada sorteio é uma leitura de fitness na arena (~3 ns).

def tourn.better(+worst: Bool, +f: U32, +bf: U32) -> Bool:
  Bool.pick(Bool, worst, U32.is_lt(f, bf), U32.is_gt(f, bf))

def tourn.idx(+worst: Bool, +cand: U32, +f: U32, +bi: U32, +bf: U32) -> U32:
  Bool.pick(U32, tourn.better(worst, f, bf), cand, bi)

def tourn.fit(+worst: Bool, +f: U32, +bf: U32) -> U32:
  Bool.pick(U32, tourn.better(worst, f, bf), f, bf)

def tourn.go(~G: Type, k: Nat, st: A.Pop<G> & U32, +worst: Bool, +cand: U32,
             +bi: U32, +bf: U32, +n: U32, +ex1: U32, +ex2: U32, +seed: U32) -> A.Pop<G> & U32:
  match k:
    case 0n:
      (p, +f) = st
      (p, tourn.idx(worst, cand, f, bi, bf))
    case 1n+q:
      (p, +f) = st
      +c2 = draw(seed, n, ex1, ex2)
      tourn.go(~G, q, A.fit_at(~G, p, c2), worst, c2,
        tourn.idx(worst, cand, f, bi, bf), tourn.fit(worst, f, bf),
        n, ex1, ex2, R.step(seed))

# `tsize` sorteios entre os `n` slots, pulando `ex1` e `ex2`.
def tournament(~G: Type, p: A.Pop<G>, +worst: Bool, +tsize: U32, +n: U32,
               +ex1: U32, +ex2: U32, +seed: U32) -> A.Pop<G> & U32:
  +c0 = draw(seed, n, ex1, ex2)
  tourn.go(~G, U32.to_nat((U32.max(tsize, 1) - 1 : U32)), A.fit_at(~G, p, c0), worst, c0, c0,
    Bool.pick(U32, worst, R.MAX(), 0), n, ex1, ex2, R.step(seed))

# ----------------------------------------------------------------
# CALLBACKS DOS OPERADORES
# ----------------------------------------------------------------

# copiar os genes do pai (2º slot) para a vítima (1º slot): a vítima vira filho
# (fitness e hash zerados), o pai fica intacto
# CRUZAMENTO "4 ENTRAM, 4 SAEM": os dois pais (no arranjo atual) e os dois
# filhos (no arranjo da próxima geração) saem dos arranjos de uma vez, o
# operador do problema lê os pais e escreve os filhos numa varredura só, e
# todos voltam. Os pais ficam INTACTOS, com fitness e hash preservados.
# CRUZAMENTO "4 ENTRAM, 4 SAEM": os dois pais (no arranjo atual) e os dois
# filhos (no da próxima geração) saem dos arranjos de uma vez, o operador do
# problema lê os pais e escreve os filhos, e todos voltam. Os pais ficam
# INTACTOS, com aptidão e hash preservados; os filhos nascem sem aptidão, que
# é calculada depois, na sua própria etapa.
def breed_cb.fin(~G: Type, r: (G & G) & (G & G), +fpa: U32, +hpa: U32, +fpb: U32, +hpb: U32) ->
  (A.Individual<G> & A.Individual<G>) & (A.Individual<G> & A.Individual<G>):
  (filhos, pais) = r
  (ga, gb) = filhos
  (gpa, gpb) = pais
  ((A.Individual{ga, 0, 0}, A.Individual{gb, 0, 0}),
   (A.Individual{gpa, fpa, hpa}, A.Individual{gpb, fpb, hpb}))

def breed_cb(~G: Type, ~P: Data, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)),
             ija: A.Individual<G>, ijb: A.Individual<G>, ipa: A.Individual<G>, ipb: A.Individual<G>,
             +call: Call<P>) -> (A.Individual<G> & A.Individual<G>) & (A.Individual<G> & A.Individual<G>):
  match ija ijb ipa ipb:
    case A.Individual{ga, fa, ha} A.Individual{gb, fb, hb} A.Individual{gpa, +fpa, +hpa} A.Individual{gpb, +fpb, +hpb}:
      breed_cb.fin(~G, breed(call_ctx(P, call), ga, gb, gpa, gpb,
        call_cross_on(P, call), call_seed(P, call)), fpa, hpa, fpb, hpb)

# ----------------------------------------------------------------
# MUTAR E AVALIAR O FILHO (etapas separadas)
# ----------------------------------------------------------------

def mut_eval.fin2(~G: Type, r: G & U32, +f: U32) -> A.Individual<G> & U32:
  (g, +h) = r
  (A.Individual{g, f, U32.max(R.mix(h), 1)}, f)

def mut_eval.fin.if(~G: Type, ~P: Data, ~hash: @+c: P -> G -> (G & U32),
                    liga: Bool, g: G, +f: U32, +call: Call<P>) -> A.Individual<G> & U32:
  match liga:
    case True{}:
      mut_eval.fin2(~G, hash(call_ctx(P, call), g), f)
    case False{}:
      (A.Individual{g, f, 0}, f)

def mut_eval.fin(~G: Type, ~P: Data, ~hash: @+c: P -> G -> (G & U32),
                 r: G & U32, +call: Call<P>) -> A.Individual<G> & U32:
  (g, +f) = r
  mut_eval.fin.if(~G, ~P, ~hash, call_hash_on(P, call), g, f, call)

def mut_eval.hit(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
                 ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
                 hit: Bool, gene: G, +call: Call<P>, +at: U32) -> A.Individual<G> & U32:
  match hit:
    case True{}:
      +s = call_seed(P, call)
      mut_eval.fin(~G, ~P, ~hash, fitness(call_ctx(P, call),
        mutate(call_ctx(P, call), gene, call_gene(P, call), R.hash32((s + at : U32)))), call)
    case False{}:
      mut_eval.fin(~G, ~P, ~hash, fitness(call_ctx(P, call), gene), call)

# `call.rate` é a chance de mutar; `gene_rate` vai junto na semente do Call
def mut_eval(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
             ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
             ind: A.Individual<G>, +call: Call<P>, +at: U32) -> A.Individual<G> & U32:
  match ind:
    case A.Individual{gene, fit, h}:
      +s = call_seed(P, call)
      mut_eval.hit(~G, ~P, ~mutate, ~fitness, ~hash,
        R.hit(R.split.fst((s + at : U32)), call_rate(P, call)),
        gene, call, at)

# ----------------------------------------------------------------
# UM EVENTO
# ----------------------------------------------------------------
# Cadeia de auxiliares NÃO recursivos (Bend 2 não tem recursão mútua): cada um
# recebe a tupla do passo anterior, abre, e passa a arena adiante.

# ----------------------------------------------------------------
# UM EVENTO
# ----------------------------------------------------------------
# Dois torneios acham os pais no arranjo ATUAL; os filhos vão para os slots
# `j` e `j+1` do arranjo da PRÓXIMA geração, percorridos em sequência. Não há
# vítima: a geração inteira é substituída de uma vez, no fim.

def ev.fim(~G: Type, r: A.Pop<G> & U32) -> A.Pop<G>:
  (p, +fb) = r
  p

def ev.mutb(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
            r: A.Pop<G> & U32, +j: U32, +ctx: P, +cfg: Config, +seed: U32) -> A.Pop<G>:
  (p, +fa) = r
  ev.fim(~G, A.read1_nxt(~G, ~Call<P>, ~U32, ~mut_eval(~G, ~P, ~mutate, ~fitness, ~hash),
    p, U32.inc(j), Call{ctx, cfg_mut(cfg), cfg_gene(cfg), R.split.snd(seed), cfg_div(cfg), False{}}))

def ev.muta(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
            p: A.Pop<G>, +j: U32, +ctx: P, +cfg: Config, +seed: U32) -> A.Pop<G>:
  ev.mutb(~G, ~P, ~mutate, ~fitness, ~hash,
    A.read1_nxt(~G, ~Call<P>, ~U32, ~mut_eval(~G, ~P, ~mutate, ~fitness, ~hash),
      p, j, Call{ctx, cfg_mut(cfg), cfg_gene(cfg), R.split.fst(seed), cfg_div(cfg), False{}}),
    j, ctx, cfg, seed)

def ev.pb(~G: Type, ~P: Data, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
          r: A.Pop<G> & U32, +pa: U32, +j: U32, +ctx: P, +cfg: Config, +seed: U32) -> A.Pop<G>:
  (p, +pb) = r
  ev.muta(~G, ~P, ~mutate, ~fitness, ~hash,
    A.at4(~G, ~Call<P>, ~breed_cb(~G, ~P, ~breed), p, pa, pb, j, U32.inc(j),
      Call{ctx, 0, 0, R.split.trd(seed), False{}, R.hit(R.split.fth(seed), cfg_cross(cfg))}),
    j, ctx, cfg, seed)

def ev.pa(~G: Type, ~P: Data, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
          r: A.Pop<G> & U32, +j: U32, +ctx: P, +cfg: Config, +n: U32, +seed: U32) -> A.Pop<G>:
  (p, +pa) = r
  ev.pb(~G, ~P, ~breed, ~mutate, ~fitness, ~hash,
    tournament(~G, p, False{}, cfg_tsize(cfg), n, pa, n, R.split.snd(seed)),
    pa, j, ctx, cfg, seed)

def event(~G: Type, ~P: Data, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
          p: A.Pop<G>, +j: U32, +ctx: P, +cfg: Config, +n: U32, +seed: U32) -> A.Pop<G>:
  ev.pa(~G, ~P, ~breed, ~mutate, ~fitness, ~hash,
    tournament(~G, p, False{}, cfg_tsize(cfg), n, n, n, R.split.fst(seed)),
    j, ctx, cfg, n, seed)

# ----------------------------------------------------------------
# DIVERSIDADE (diversity check)
# ----------------------------------------------------------------
# Uma passada pelos slots marcando o hash de cada indivíduo num conjunto de
# bits; quem repetir um hash já visto é mutado de novo (com 4× a taxa por
# gene), reavaliado e re-hasheado, e é o hash NOVO que é marcado.
#
# Os hashes já vêm prontos do nascimento, então a passada é só leitura (3 ns
# por indivíduo) mais a remutação de quem repetiu. O conjunto tem 2^16 bits
# (2048 palavras): uma colisão entre hashes diferentes custa uma mutação a
# mais, e nada mais.

def bits_d() -> Nat:
  11n                          # 2048 palavras = 2^16 bits

def bit_word(+h: U32) -> U32:
  U32.and(U32.shrn(h, 5n), 2047)

def bit_mask(+h: U32) -> U32:
  U32.shln(1, U32.to_nat(U32.and(h, 31)))

# marca o hash e diz se ELE JÁ ESTAVA marcado
def seen_mark.fin(r: Array<U32> & U32, +h: U32) -> Array<U32> & Bool:
  (seen, +w) = r
  (Array.set(U32, seen, bit_word(h), U32.or(w, bit_mask(h))),
   U32.is_ne(U32.and(w, bit_mask(h)), 0))

def seen_mark(seen: Array<U32>, +h: U32) -> Array<U32> & Bool:
  seen_mark.fin(Array.get(U32, seen, bit_word(h)), h)

def div.hash_of(~G: Type, r: A.Individual<G> & U32) -> A.Individual<G> & U32:
  (ind, f) = r
  A.peek_hash(~G, ind, 0, 0)

def div.remut(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
              ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
              ind: A.Individual<G>, +call: Call<P>, +at: U32) -> A.Individual<G> & U32:
  match ind:
    case A.Individual{gene, fit, h}:
      +s = call_seed(P, call)
      mut_eval.fin(~G, ~P, ~hash, fitness(call_ctx(P, call),
        mutate(call_ctx(P, call), gene, call_gene(P, call), R.hash32((s + at : U32)))), call)

def div.remut2(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
               ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
               ind: A.Individual<G>, +call: Call<P>, +at: U32) -> A.Individual<G> & U32:
  div.hash_of(~G, div.remut(~G, ~P, ~mutate, ~fitness, ~hash, ind, call, at))

def div.dup(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
            ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
            repetiu: Bool, p: A.Pop<G>, +i: U32, +call: Call<P>) -> A.Pop<G> & U32:
  match repetiu:
    case True{}:
      A.read1(~G, ~Call<P>, ~U32, ~div.remut2(~G, ~P, ~mutate, ~fitness, ~hash), p, i, call)
    case False{}:
      (p, 0)

def div.slot3(~G: Type, r: A.Pop<G> & U32, seen: Array<U32>) -> (A.Pop<G> & Array<U32>) & U32:
  (p, +novo) = r
  (T.pair(A.Pop<G>, Array<U32>, p, seen), novo)

def div.remark2(~G: Type, p: A.Pop<G>, mk: Array<U32> & Bool) -> A.Pop<G> & Array<U32>:
  (seen, rep) = mk
  T.pair(A.Pop<G>, Array<U32>, p, seen)

# Bool.pick avaliaria os DOIS lados e duplicaria o `seen`, que é um Array:
# a escolha tem de ser um `match` sobre um Bool que o chamador já calculou
def div.remark.if(~G: Type, tem: Bool, p: A.Pop<G>, seen: Array<U32>, +novo: U32) -> A.Pop<G> & Array<U32>:
  match tem:
    case True{}:
      div.remark2(~G, p, seen_mark(seen, novo))
    case False{}:
      T.pair(A.Pop<G>, Array<U32>, p, seen)

def div.remark(~G: Type, st: (A.Pop<G> & Array<U32>) & U32) -> A.Pop<G> & Array<U32>:
  (ps, +novo) = st
  (p, seen) = ps
  div.remark.if(~G, U32.is_ne(novo, 0), p, seen, novo)

# o elite (slot `skip`) nunca é remutado
def div.slot2(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
              ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
              p: A.Pop<G>, mk: Array<U32> & Bool, +i: U32, +skip: U32, +call: Call<P>) -> (A.Pop<G> & Array<U32>) & U32:
  (seen, repetiu) = mk
  div.slot3(~G, div.dup(~G, ~P, ~mutate, ~fitness, ~hash,
    Bool.and(repetiu, U32.is_ne(i, skip)), p, i, call), seen)

def div.slot(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
             ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
             r: A.Pop<G> & U32, seen: Array<U32>, +i: U32, +skip: U32, +call: Call<P>) -> A.Pop<G> & Array<U32>:
  (p, +h) = r
  div.remark(~G, div.slot2(~G, ~P, ~mutate, ~fitness, ~hash, p, seen_mark(seen, h), i, skip, call))

def div.go(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
           ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
           k: Nat, st: A.Pop<G> & Array<U32>, +i: U32, +skip: U32, +call: Call<P>) -> A.Pop<G> & Array<U32>:
  match k:
    case 0n:
      st
    case 1n+q:
      (p, seen) = st
      div.go(~G, ~P, ~mutate, ~fitness, ~hash, q,
        div.slot(~G, ~P, ~mutate, ~fitness, ~hash, A.hash_at(~G, p, i), seen, i, skip, call),
        (i + 1 : U32), skip, call)

# limpa o conjunto e percorre a população
def diversify(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
              ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
              p: A.Pop<G>, seen: Array<U32>, +n: U32, +skip: U32, +call: Call<P>) -> A.Pop<G> & Array<U32>:
  div.go(~G, ~P, ~mutate, ~fitness, ~hash, U32.to_nat(n),
    T.pair(A.Pop<G>, Array<U32>, p, Arr.fill(~U32, seen, 0, 0, 2048)), 0, skip, call)

# ----------------------------------------------------------------
# GERAÇÃO E EVOLUÇÃO
# ----------------------------------------------------------------

# O conjunto de bits é rascunho da ÉPOCA: entra e sai junto com o estado, sem
# ser realocado a cada geração.
def gen.div2(~G: Type, r: A.Pop<G> & Array<U32>, +bi: U32, +bf: U32, +stag: U32, +seed: U32) -> Run<G> & Array<U32>:
  (p, seen) = r
  (Run{p, bi, bf, stag, seed}, seen)

def gen.div(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
            ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
            run: Run<G>, seen: Array<U32>, +ctx: P, +cfg: Config, +n: U32) -> Run<G> & Array<U32>:
  match run:
    case Run{pop, +bi, +bf, +stag, +seed}:
      gen.div2(~G, diversify(~G, ~P, ~mutate, ~fitness, ~hash, pop, seen, n, bi,
        Call{ctx, 0, R.scale(cfg_gene(cfg), {4.0 : F32}), R.split.fth(seed), True{}, False{}}), bi, bf, stag, R.step(seed))

def gen.div.if(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
               ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
               liga: Bool, run: Run<G>, seen: Array<U32>, +ctx: P, +cfg: Config, +n: U32) -> Run<G> & Array<U32>:
  match liga:
    case True{}:
      gen.div(~G, ~P, ~mutate, ~fitness, ~hash, run, seen, ctx, cfg, n)
    case False{}:
      T.pair(Run<G>, Array<U32>, run, seen)

# ----------------------------------------------------------------
# ESTAGNAÇÃO
# ----------------------------------------------------------------
# `stag` conta gerações sem melhora. Na metade de `max_stag` a mutação dobra
# (mais exploração); passando de `max_stag`, a população é reiniciada com
# `~init`, poupando o elite — e o contador zera. Com `max_stag = 0` nada
# disso acontece.

# a configuração EFETIVA desta geração
def eff_cfg(+cfg: Config, +stag: U32) -> Config:
  +limite = cfg_stag(cfg)
  +forte = Bool.and(U32.is_ne(limite, 0), U32.is_ge(stag, U32.shr(limite)))
  Config{cfg_cross(cfg),
         Bool.pick(U32, forte, R.scale(cfg_mut(cfg), {2.0 : F32}), cfg_mut(cfg)),
         Bool.pick(U32, forte, R.scale(cfg_gene(cfg), {2.0 : F32}), cfg_gene(cfg)),
         cfg_tsize(cfg), cfg_div(cfg), limite}

# reinício: cada slot (menos o elite) recebe um genoma novo de `~init`, é
# avaliado e re-hasheado. É in-place: `~init` escreve no buffer que já existe.
def restart.one(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G,
                ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
                ind: A.Individual<G>, +call: Call<P>, +at: U32) -> A.Individual<G> & U32:
  match ind:
    case A.Individual{gene, fit, h}:
      +s = call_seed(P, call)
      mut_eval.fin(~G, ~P, ~hash,
        fitness(call_ctx(P, call), init(call_ctx(P, call), gene, R.hash32((s + at : U32)))), call)

def restart.skip(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G,
                 ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
                 pular: Bool, p: A.Pop<G>, +i: U32, +call: Call<P>) -> A.Pop<G> & U32:
  match pular:
    case True{}:
      (p, 0)
    case False{}:
      A.read1(~G, ~Call<P>, ~U32, ~restart.one(~G, ~P, ~init, ~fitness, ~hash), p, i, call)

def restart.go(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G,
               ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
               k: Nat, r: A.Pop<G> & U32, +i: U32, +skip: U32, +call: Call<P>) -> A.Pop<G>:
  match k:
    case 0n:
      (p, +f) = r
      p
    case 1n+q:
      (p, +f) = r
      restart.go(~G, ~P, ~init, ~fitness, ~hash, q,
        restart.skip(~G, ~P, ~init, ~fitness, ~hash, U32.is_eq(i, skip), p, i, call),
        (i + 1 : U32), skip, call)

def restart(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G,
            ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
            p: A.Pop<G>, +n: U32, +skip: U32, +call: Call<P>) -> A.Pop<G>:
  restart.go(~G, ~P, ~init, ~fitness, ~hash, U32.to_nat(n), (p, 0), 0, skip, call)

# depois da geração: conta a estagnação e, se passou do limite, reinicia
def stag.fin(~G: Type, p: A.Pop<G>, seen: Array<U32>, +bi: U32, +bf: U32, +stag: U32, +seed: U32) -> Run<G> & Array<U32>:
  T.pair(Run<G>, Array<U32>, Run{p, bi, bf, stag, seed}, seen)

def stag.if(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G,
            ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
            reinicia: Bool, p: A.Pop<G>, seen: Array<U32>, +bi: U32, +bf: U32, +stag: U32,
            +ctx: P, +cfg: Config, +n: U32, +seed: U32) -> Run<G> & Array<U32>:
  match reinicia:
    case True{}:
      stag.fin(~G, restart(~G, ~P, ~init, ~fitness, ~hash, p, n, bi,
        Call{ctx, 0, 0, R.split.snd(seed), cfg_div(cfg), False{}}), seen, bi, bf, 0, R.step(seed))
    case False{}:
      stag.fin(~G, p, seen, bi, bf, stag, seed)

def stag.conta(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G,
               ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
               run: Run<G>, seen: Array<U32>, +antes: U32, +ctx: P, +cfg: Config, +n: U32) -> Run<G> & Array<U32>:
  match run:
    case Run{pop, +bi, +bf, stag, +seed}:
      +novo_stag = Bool.pick(U32, U32.is_gt(bf, antes), 0, U32.inc(stag))
      +limite = cfg_stag(cfg)
      stag.if(~G, ~P, ~init, ~fitness, ~hash,
        Bool.and(U32.is_ne(limite, 0), U32.is_gt(novo_stag, limite)),
        pop, seen, bi, bf, novo_stag, ctx, cfg, n, seed)

def stag.open(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G,
              ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
              st: Run<G> & Array<U32>, +antes: U32, +ctx: P, +cfg: Config, +n: U32) -> Run<G> & Array<U32>:
  (run, seen) = st
  stag.conta(~G, ~P, ~init, ~fitness, ~hash, run, seen, antes, ctx, cfg, n)

# ----------------------------------------------------------------
# UMA GERAÇÃO
# ----------------------------------------------------------------
#   1. `size/2` eventos preenchem o arranjo da próxima geração, em sequência
#   2. o elite ANDA para o slot 0 (troca de handle, zero gene copiado)
#   3. os dois arranjos trocam de papel (troca de handle)
#   4. uma varredura acha o melhor da nova geração (todos já têm fitness)
#   5. diversidade e estagnação, como antes

def gen.go(~G: Type, ~P: Data, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
           k: Nat, p: A.Pop<G>, +j: U32, +ctx: P, +cfg: Config, +n: U32, +seed: U32) -> A.Pop<G>:
  match k:
    case 0n:
      p
    case 1n+q:
      gen.go(~G, ~P, ~breed, ~mutate, ~fitness, ~hash, q,
        event(~G, ~P, ~breed, ~mutate, ~fitness, ~hash, p, j, ctx, cfg, n, seed),
        (j + 2 : U32), ctx, cfg, n, R.step(seed))

def gen.fim2(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
             p: A.Pop<G>, best: U32 & U32, seen: Array<U32>, +antes: U32, +stag: U32,
             +ctx: P, +cfg: Config, +n: U32, +seed: U32) -> Run<G> & Array<U32>:
  (+bi, +bf) = best
  stag.open(~G, ~P, ~init, ~fitness, ~hash,
    gen.div.if(~G, ~P, ~mutate, ~fitness, ~hash, cfg_div(cfg),
      Run{p, bi, bf, stag, seed}, seen, ctx, cfg, n),
    antes, ctx, cfg, n)

# depois da varredura: diversidade e estagnação
def gen.fim(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
            r: A.Pop<G> & (U32 & U32), seen: Array<U32>, +antes: U32, +stag: U32,
            +ctx: P, +cfg: Config, +n: U32, +seed: U32) -> Run<G> & Array<U32>:
  (p, best) = r
  gen.fim2(~G, ~P, ~init, ~mutate, ~fitness, ~hash, p, best, seen, antes, stag, ctx, cfg, n, seed)

def generation(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
               run: Run<G>, seen: Array<U32>, +antes: U32, +stag: U32,
               +ctx: P, +cfg: Config, +n: U32) -> Run<G> & Array<U32>:
  match run:
    case Run{pop, +bi, bf, st, +seed}:
      gen.fim(~G, ~P, ~init, ~mutate, ~fitness, ~hash,
        A.evaluate(~G, ~P, ~fitness,
          A.swap_gen(~G, A.elite_to_nxt(~G,
            gen.go(~G, ~P, ~breed, ~mutate, ~fitness, ~hash, U32.to_nat(U32.shr(n)),
                   pop, 0, ctx, eff_cfg(cfg, stag), n, R.split.fst(seed)),
            bi)),
          ctx),
        seen, antes, stag, ctx, cfg, n, R.step(seed))

def evolve.step(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
                run: Run<G>, seen: Array<U32>, +ctx: P, +cfg: Config, +n: U32) -> Run<G> & Array<U32>:
  match run:
    case Run{pop, +bi, +bf, +stag, +seed}:
      generation(~G, ~P, ~init, ~breed, ~mutate, ~fitness, ~hash,
        Run{pop, bi, bf, stag, seed}, seen, bf, stag, ctx, cfg, n)

def evolve(~G: Type, ~P: Data, ~init: @+c: P -> G -> @+s: U32 -> G, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
           k: Nat, st: Run<G> & Array<U32>, +ctx: P, +cfg: Config, +n: U32) -> Run<G> & Array<U32>:
  match k:
    case 0n:
      st
    case 1n+q:
      (run, seen) = st
      evolve(~G, ~P, ~init, ~breed, ~mutate, ~fitness, ~hash, q,
        evolve.step(~G, ~P, ~init, ~breed, ~mutate, ~fitness, ~hash, run, seen, ctx, cfg, n),
        ctx, cfg, n)

# ----------------------------------------------------------------
# COMEÇO E FIM
# ----------------------------------------------------------------

# A primeira avaliação, que dá o melhor inicial
def start.fin2(~G: Type, p: A.Pop<G>, best: U32 & U32, +seed: U32) -> Run<G>:
  (+bi, +bf) = best
  Run{p, bi, bf, 0, seed}

def start.fin(~G: Type, r: A.Pop<G> & (U32 & U32), +seed: U32) -> Run<G>:
  (p, best) = r
  start.fin2(~G, p, best, seed)

def start(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
          p: A.Pop<G>, +ctx: P, +seed: U32) -> Run<G>:
  start.fin(~G, A.evaluate(~G, ~P, ~fitness, p, ctx), seed)

# O melhor da corrida, sem consumir o estado
def best_of(~G: Type, run: Run<G>) -> Run<G> & U32:
  match run:
    case Run{pop, +bi, +bf, +stag, +seed}:
      (Run{pop, bi, bf, stag, seed}, bf)

# ----------------------------------------------------------------
# ARQUIPÉLAGO: DEMES EM PARALELO
# ----------------------------------------------------------------
# A população é dividida em 2^d demes com `match ANode`, cada um evoluindo
# numa tarefa. Dividir custa só cópia de HANDLES (um por indivíduo), não de
# genes — é o que torna o paralelismo barato aqui.
#
# Cada deme precisa dos SEUS dois buracos: um valor linear não se compartilha
# entre tarefas. A divisão aloca dois genomas por deme, uma vez por ÉPOCA (não
# por geração); a junção os descarta.
#
# A migração troca slots entre as duas metades (`Arr.swap_range_hole`): troca
# de handle, nenhum gene copiado. Depois da junção, uma passada de
# `A.evaluate` acha o melhor do conjunto — como todos já têm fitness, ela é só
# uma varredura de ~3 ns por indivíduo.

# ---- migração e junção (agora os DOIS arranjos) ----

def arch.mig.fin(~G: Type, st: (Array<A.Individual<G>> & Array<A.Individual<G>>) & A.Individual<G>,
                 nxt_l: Array<A.Individual<G>>, nxt_r: Array<A.Individual<G>>,
                 h2: A.Individual<G>, h3: A.Individual<G>, h4: A.Individual<G>, +half: U32) -> A.Pop<G>:
  (ab, h1) = st
  (cur_l, cur_r) = ab
  A.Pop{ANode{cur_l, cur_r}, ANode{nxt_l, nxt_r}, h1, h2, h3, h4, U32.shl(half)}

def arch.mig2(~G: Type, st: (Array<A.Individual<G>> & Array<A.Individual<G>>) & A.Individual<G>,
              nxt_l: Array<A.Individual<G>>, nxt_r: Array<A.Individual<G>>,
              h2: A.Individual<G>, h3: A.Individual<G>, h4: A.Individual<G>,
              +br: U32, +half: U32) -> A.Pop<G>:
  (ab, h1) = st
  (cur_l, cur_r) = ab
  arch.mig.fin(~G, Arr.swap_range_hole(~A.Individual<G>, cur_l, cur_r, h1, br, 1),
               nxt_l, nxt_r, h2, h3, h4, half)

# duas trocas de slot entre as metades da geração ATUAL: o melhor de cada lado
# troca com o mesmo índice do outro. Troca de handle, nenhum gene copiado.
def arch.mig(~G: Type, cur_l: Array<A.Individual<G>>, cur_r: Array<A.Individual<G>>,
             nxt_l: Array<A.Individual<G>>, nxt_r: Array<A.Individual<G>>,
             h1: A.Individual<G>, h2: A.Individual<G>, h3: A.Individual<G>, h4: A.Individual<G>,
             +bl: U32, +br: U32, +half: U32) -> A.Pop<G>:
  arch.mig2(~G, Arr.swap_range_hole(~A.Individual<G>, cur_l, cur_r, h1, bl, 1),
            nxt_l, nxt_r, h2, h3, h4, br, half)

def arch.merge.r(~G: Type, cur_l: Array<A.Individual<G>>, nxt_l: Array<A.Individual<G>>,
                 h1: A.Individual<G>, h2: A.Individual<G>, h3: A.Individual<G>, h4: A.Individual<G>,
                 pr: A.Pop<G>, +bl: U32, +br: U32) -> A.Pop<G>:
  match pr:
    case A.Pop{cur_r, nxt_r, r1, r2, r3, r4, +sr}:
      arch.mig(~G, cur_l, cur_r, nxt_l, nxt_r, h1, h2, h3, h4, bl, br, sr)

def arch.merge.left(~G: Type, pl: A.Pop<G>, pr: A.Pop<G>, +bl: U32, +br: U32) -> A.Pop<G>:
  match pl:
    case A.Pop{cur_l, nxt_l, h1, h2, h3, h4, sl}:
      arch.merge.r(~G, cur_l, nxt_l, h1, h2, h3, h4, pr, bl, br)

def arch.merge.runs(~G: Type, l: Run<G>, pr: A.Pop<G>, +br: U32, +seed: U32) -> Run<G> & U32:
  match l:
    case Run{pl, +bl, bf, st, sl}:
      (Run{arch.merge.left(~G, pl, pr, bl, br), 0, 0, st, seed}, bl)

def arch.merge.open_r(~G: Type, l: Run<G>, r: Run<G>) -> Run<G> & U32:
  match r:
    case Run{pr, +br, bf, st, +sr}:
      arch.merge.runs(~G, l, pr, br, R.split.trd(sr))

# junta as duas metades (com migração) e reavalia para achar o melhor do todo
def arch.merge.fin(~G: Type, r: A.Pop<G> & (U32 & U32), +seed: U32) -> Run<G>:
  (p, best) = r
  start.fin2(~G, p, best, seed)

def arch.merge.eval2(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
                     run: Run<G>, +ctx: P) -> Run<G>:
  match run:
    case Run{pop, bi, bf, +stag, +seed}:
      arch.merge.fin(~G, A.evaluate(~G, ~P, ~fitness, pop, ctx), seed)

def arch.merge.eval(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
                    r: Run<G> & U32, +ctx: P) -> Run<G>:
  (run, +bl) = r
  arch.merge.eval2(~G, ~P, ~fitness, run, ctx)

def arch.merge(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
               l: Run<G>, r: Run<G>, +ctx: P) -> Run<G>:
  arch.merge.eval(~G, ~P, ~fitness, arch.merge.open_r(~G, l, r), ctx)

# ---- a recursão paralela ----

# junta os dois demes: fica com o conjunto de bits da esquerda e descarta o da
# direita (junto com os dois buracos dela)
def arch.merge2(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
                l: Run<G> & Array<U32>, r: Run<G> & Array<U32>, +ctx: P) -> Run<G> & Array<U32>:
  (run_l, seen_l) = l
  (run_r, seen_r) = r
  T.pair(Run<G>, Array<U32>, arch.merge(~G, ~P, ~fitness, run_l, run_r, ctx), seen_l)

def arch.go(~G: Type, ~P: Data, ~alloc: @+c: P -> G, ~init: @+c: P -> G -> @+s: U32 -> G, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
            d: Nat, st: Run<G> & Array<U32>, +ctx: P, +cfg: Config, +gens: U32, +n: U32) -> Run<G> & Array<U32>:
  match d:
    case 0n:
      evolve(~G, ~P, ~init, ~breed, ~mutate, ~fitness, ~hash, U32.to_nat(gens), st, ctx, cfg, n)
    case 1n+ +p:
      # a divisão é aberta AQUI dentro (matches aninhados sobre campos): um
      # auxiliar que abrisse os pares teria de chamar `arch.go` de volta, e
      # Bend 2 não tem recursão mútua
      (run, seen) = st
      match run:
        case Run{pop, bi, bf, +stag, +seed}:
          match pop:
            case A.Pop{cur, nxt, h1, h2, h3, h4, +size}:
              match cur:
                case ALeaf{x}:
                  # deme de um indivíduo: nada a dividir (não ocorre com
                  # d <= log2(pop), que é o contrato de `archipelago`)
                  evolve(~G, ~P, ~init, ~breed, ~mutate, ~fitness, ~hash, U32.to_nat(gens),
                    T.pair(Run<G>, Array<U32>, Run{A.Pop{ALeaf{x}, nxt, h1, h2, h3, h4, size}, bi, bf, stag, seed}, seen), ctx, cfg, n)
                case ANode{cur_l, cur_r}:
                  match nxt:
                    case ALeaf{y}:
                      evolve(~G, ~P, ~init, ~breed, ~mutate, ~fitness, ~hash, U32.to_nat(gens),
                        T.pair(Run<G>, Array<U32>, Run{A.Pop{ANode{cur_l, cur_r}, ALeaf{y}, h1, h2, h3, h4, size}, bi, bf, stag, seed}, seen), ctx, cfg, n)
                    case ANode{nxt_l, nxt_r}:
                      # cada deme leva os SEUS quatro buracos e o SEU conjunto
                      # de bits: valor linear não se compartilha entre tarefas.
                      # São 4 genomas + 8 KB por deme, uma vez por época.
                      +half = U32.shr(size)
                      l r = arch.go(~G, ~P, ~alloc, ~init, ~breed, ~mutate, ~fitness, ~hash, p, T.pair(Run<G>, Array<U32>, Run{A.Pop{cur_l, nxt_l, h1, h2, h3, h4, half}, 0, 0, stag, R.split.fst(seed)}, seen), ctx, cfg, gens, half) arch.go(~G, ~P, ~alloc, ~init, ~breed, ~mutate, ~fitness, ~hash, p, T.pair(Run<G>, Array<U32>, Run{A.Pop{cur_r, nxt_r, A.fresh(~G, alloc(ctx)), A.fresh(~G, alloc(ctx)), A.fresh(~G, alloc(ctx)), A.fresh(~G, alloc(ctx)), half}, 0, 0, stag, R.split.snd(seed)}, Array.new(U32, bits_d(), 0)), ctx, cfg, gens, half)
                  arch.merge2(~G, ~P, ~fitness, l, r, ctx)

# `epochs` épocas de `gens` gerações em cada um dos 2^d demes, com migração
# entre as metades ao fim de cada época.
def archipelago(~G: Type, ~P: Data, ~alloc: @+c: P -> G, ~init: @+c: P -> G -> @+s: U32 -> G, ~breed: @+c: P -> G -> G -> G -> G -> @cruza: Bool -> @+s: U32 -> ((G & G) & (G & G)), ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32), ~hash: @+c: P -> G -> (G & U32),
                epochs: Nat, +d: Nat, st: Run<G> & Array<U32>, +ctx: P, +cfg: Config, +gens: U32, +n: U32) -> Run<G> & Array<U32>:
  match epochs:
    case 0n:
      st
    case 1n+q:
      archipelago(~G, ~P, ~alloc, ~init, ~breed, ~mutate, ~fitness, ~hash, q, d,
        arch.go(~G, ~P, ~alloc, ~init, ~breed, ~mutate, ~fitness, ~hash, d, st, ctx, cfg, gens, n),
        ctx, cfg, gens, n)

# o estado inicial de uma corrida: população avaliada e o conjunto de bits
def start_st(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
             p: A.Pop<G>, +ctx: P, +seed: U32) -> Run<G> & Array<U32>:
  T.pair(Run<G>, Array<U32>, start(~G, ~P, ~fitness, p, ctx, seed), Array.new(U32, bits_d(), 0))

def best_st2(~G: Type, r: Run<G> & U32, seen: Array<U32>) -> (Run<G> & Array<U32>) & U32:
  (run, +bf) = r
  (T.pair(Run<G>, Array<U32>, run, seen), bf)

# o melhor de um estado
def best_st(~G: Type, st: Run<G> & Array<U32>) -> (Run<G> & Array<U32>) & U32:
  (run, seen) = st
  best_st2(~G, best_of(~G, run), seen)
