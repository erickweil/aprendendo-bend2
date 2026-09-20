import Base
import ./arena.bend as A
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
  Config{cross_rate: U32, mut_rate: U32, gene_rate: U32, tsize: U32}

def cfg_new(+cross_rate: U32, +mut_rate: U32, +gene_rate: U32, +tsize: U32) -> Config:
  Config{cross_rate, mut_rate, gene_rate, tsize}

def cfg_cross(+cfg: Config) -> U32:
  match cfg:
    case Config{+cross_rate, mut_rate, gene_rate, tsize}:
      cross_rate

def cfg_mut(+cfg: Config) -> U32:
  match cfg:
    case Config{cross_rate, +mut_rate, gene_rate, tsize}:
      mut_rate

def cfg_gene(+cfg: Config) -> U32:
  match cfg:
    case Config{cross_rate, mut_rate, +gene_rate, tsize}:
      gene_rate

def cfg_tsize(+cfg: Config) -> U32:
  match cfg:
    case Config{cross_rate, mut_rate, gene_rate, +tsize}:
      tsize

# O que uma callback precisa saber. `Data`, porque as callbacks recebem com `+`.
type Call<-P: Data> is Data:
  Call{ctx: P, rate: U32, gene_rate: U32, seed: U32}

def call_ctx(-P: Data, +c: Call<P>) -> P:
  match c:
    case Call{+ctx, rate, gene_rate, seed}:
      ctx

def call_rate(-P: Data, +c: Call<P>) -> U32:
  match c:
    case Call{ctx, +rate, gene_rate, seed}:
      rate

# a taxa POR GENE viaja no record, e não como argumento template: template só
# aceita argumento comptime, e isto vem da Config em tempo de execução
def call_gene(-P: Data, +c: Call<P>) -> U32:
  match c:
    case Call{ctx, rate, +gene_rate, seed}:
      gene_rate

def call_seed(-P: Data, +c: Call<P>) -> U32:
  match c:
    case Call{ctx, rate, gene_rate, +seed}:
      seed

# Os escalares de um evento, para não carregar seis parâmetros em cada passo.
type Ev is Data:
  Ev{va: U32, vb: U32, best_idx: U32, best_fit: U32, seed: U32}

def ev_va(+e: Ev) -> U32:
  match e:
    case Ev{+va, vb, bi, bf, seed}:
      va

def ev_vb(+e: Ev) -> U32:
  match e:
    case Ev{va, +vb, bi, bf, seed}:
      vb

def ev_bi(+e: Ev) -> U32:
  match e:
    case Ev{va, vb, +bi, bf, seed}:
      bi

def ev_bf(+e: Ev) -> U32:
  match e:
    case Ev{va, vb, bi, +bf, seed}:
      bf

def ev_seed(+e: Ev) -> U32:
  match e:
    case Ev{va, vb, bi, bf, +seed}:
      seed

def ev_set_va(+e: Ev, +va: U32) -> Ev:
  Ev{va, ev_vb(e), ev_bi(e), ev_bf(e), ev_seed(e)}

def ev_set_vb(+e: Ev, +vb: U32) -> Ev:
  Ev{ev_va(e), vb, ev_bi(e), ev_bf(e), ev_seed(e)}

# O estado de uma corrida.
type Run<-G: Type> is Type:
  Run{pop: A.Pop<G>, best_idx: U32, best_fit: U32, seed: U32}

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
def copy_cb.fin(~G: Type, r: G & G, +fp: U32, +hp: U32) -> A.Individual<G> & A.Individual<G>:
  (gv, gp) = r
  (A.Individual{gv, 0, 0}, A.Individual{gp, fp, hp})

def copy_cb(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
            iv: A.Individual<G>, ip: A.Individual<G>, +call: Call<P>) -> A.Individual<G> & A.Individual<G>:
  match iv ip:
    case A.Individual{gv, fv, hv} A.Individual{gp, +fp, +hp}:
      copy_cb.fin(~G, copy_into(call_ctx(P, call), gv, gp), fp, hp)

# cruzar os dois filhos entre si, in-place
def cross_cb.fin(~G: Type, r: G & G) -> A.Individual<G> & A.Individual<G>:
  (ga, gb) = r
  (A.Individual{ga, 0, 0}, A.Individual{gb, 0, 0})

def cross_cb(~G: Type, ~P: Data, ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
             ia: A.Individual<G>, ib: A.Individual<G>, +call: Call<P>) -> A.Individual<G> & A.Individual<G>:
  match ia ib:
    case A.Individual{ga, fa, ha} A.Individual{gb, fb, hb}:
      cross_cb.fin(~G, crossover(call_ctx(P, call), ga, gb, call_seed(P, call)))

# mutar (com probabilidade) e avaliar na hora
def mut_eval.fin(~G: Type, r: G & U32) -> A.Individual<G> & U32:
  (g, +f) = r
  (A.Individual{g, f, 0}, f)

def mut_eval.hit(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
                 ~fitness: @+c: P -> G -> (G & U32),
                 hit: Bool, gene: G, +call: Call<P>, +at: U32) -> A.Individual<G> & U32:
  match hit:
    case True{}:
      +s = call_seed(P, call)
      mut_eval.fin(~G, fitness(call_ctx(P, call),
        mutate(call_ctx(P, call), gene, call_gene(P, call), R.hash32((s + at : U32)))))
    case False{}:
      mut_eval.fin(~G, fitness(call_ctx(P, call), gene))

# `call.rate` é a chance de mutar; `gene_rate` vai junto na semente do Call
def mut_eval(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
             ~fitness: @+c: P -> G -> (G & U32),
             ind: A.Individual<G>, +call: Call<P>, +at: U32) -> A.Individual<G> & U32:
  match ind:
    case A.Individual{gene, fit, hash}:
      +s = call_seed(P, call)
      mut_eval.hit(~G, ~P, ~mutate, ~fitness,
        R.hit(R.split.fst((s + at : U32)), call_rate(P, call)),
        gene, call, at)

# ----------------------------------------------------------------
# UM EVENTO
# ----------------------------------------------------------------
# Cadeia de auxiliares NÃO recursivos (Bend 2 não tem recursão mútua): cada um
# recebe a tupla do passo anterior, abre, e passa a arena adiante.

def melhor(+bi: U32, +bf: U32, +i: U32, +f: U32) -> U32 & U32:
  +ganhou = U32.is_gt(f, bf)
  (Bool.pick(U32, ganhou, i, bi), Bool.pick(U32, ganhou, f, bf))

# a semente do PRÓXIMO evento: o corpo do evento só usa os `split.*` desta
# semente, então `step` é um fluxo que não se sobrepõe a nenhum deles
# (Armadilha 9: dois consumidores do mesmo fluxo repetem os mesmos números)
def ev.s6c(~G: Type, p: A.Pop<G>, best: U32 & U32, +seed: U32) -> Run<G>:
  (+b1, +b2) = best
  Run{p, b1, b2, R.step(seed)}

def ev.s6b(~G: Type, p: A.Pop<G>, best: U32 & U32, +vb: U32, +fb: U32, +seed: U32) -> Run<G>:
  (+b1, +b2) = best
  ev.s6c(~G, p, melhor(b1, b2, vb, fb), seed)

def ev.s6(~G: Type, r: A.Pop<G> & U32, +e: Ev, +fa: U32) -> Run<G>:
  (p, +fb) = r
  ev.s6b(~G, p, melhor(ev_bi(e), ev_bf(e), ev_va(e), fa), ev_vb(e), fb, ev_seed(e))

def ev.s5(~G: Type, ~P: Data, ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G,
          ~fitness: @+c: P -> G -> (G & U32),
          r: A.Pop<G> & U32, +e: Ev, +ctx: P, +cfg: Config) -> Run<G>:
  (p, +fa) = r
  ev.s6(~G, A.read1(~G, ~Call<P>, ~U32, ~mut_eval(~G, ~P, ~mutate, ~fitness),
          p, ev_vb(e), Call{ctx, cfg_mut(cfg), cfg_gene(cfg), R.split.snd(ev_seed(e))}), e, fa)

def ev.s4(~G: Type, ~P: Data, ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
          ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
          p: A.Pop<G>, +e: Ev, +ctx: P, +cfg: Config) -> Run<G>:
  ev.s5(~G, ~P, ~mutate, ~fitness,
    A.read1(~G, ~Call<P>, ~U32, ~mut_eval(~G, ~P, ~mutate, ~fitness),
      p, ev_va(e), Call{ctx, cfg_mut(cfg), cfg_gene(cfg), R.split.fst(ev_seed(e))}),
    e, ctx, cfg)

def ev.s4_maybe(~G: Type, ~P: Data, ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
                ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
                cruza: Bool, p: A.Pop<G>, +e: Ev, +ctx: P, +cfg: Config) -> Run<G>:
  match cruza:
    case True{}:
      ev.s4(~G, ~P, ~crossover, ~mutate, ~fitness,
        A.at2(~G, ~Call<P>, ~cross_cb(~G, ~P, ~crossover), p, ev_va(e), ev_vb(e),
              Call{ctx, 0, 0, R.split.trd(ev_seed(e))}), e, ctx, cfg)
    case False{}:
      ev.s4(~G, ~P, ~crossover, ~mutate, ~fitness, p, e, ctx, cfg)

def ev.s3c(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
           ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
           ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
           r: A.Pop<G> & U32, +e: Ev, +ctx: P, +cfg: Config) -> Run<G>:
  (p, +pb) = r
  ev.s4_maybe(~G, ~P, ~crossover, ~mutate, ~fitness,
    R.hit(R.split.fth(ev_seed(e)), cfg_cross(cfg)),
    A.at2(~G, ~Call<P>, ~copy_cb(~G, ~P, ~copy_into), p, ev_vb(e), pb, Call{ctx, 0, 0, 0}),
    e, ctx, cfg)

def ev.s3a(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
           ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
           ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
           p: A.Pop<G>, +e: Ev, +ctx: P, +cfg: Config, +n: U32) -> Run<G>:
  ev.s3c(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness,
    tournament(~G, p, False{}, cfg_tsize(cfg), n, n, n, R.split.snd(R.split.fst(ev_seed(e)))),
    e, ctx, cfg)

def ev.s2(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
          ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
          ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
          r: A.Pop<G> & U32, +e: Ev, +ctx: P, +cfg: Config, +n: U32) -> Run<G>:
  (p, +pa) = r
  ev.s3a(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness,
    A.at2(~G, ~Call<P>, ~copy_cb(~G, ~P, ~copy_into), p, ev_va(e), pa, Call{ctx, 0, 0, 0}),
    e, ctx, cfg, n)

def ev.s1b(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
           ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
           ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
           r: A.Pop<G> & U32, +e: Ev, +ctx: P, +cfg: Config, +n: U32) -> Run<G>:
  (p, +vb) = r
  ev.s2(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness,
    tournament(~G, p, False{}, cfg_tsize(cfg), n, n, n, R.split.fst(ev_seed(e))),
    ev_set_vb(e, vb), ctx, cfg, n)

def ev.s1a(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
           ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
           ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
           r: A.Pop<G> & U32, +e: Ev, +ctx: P, +cfg: Config, +n: U32) -> Run<G>:
  (p, +va) = r
  ev.s1b(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness,
    tournament(~G, p, True{}, cfg_tsize(cfg), n, ev_bi(e), va, R.split.trd(ev_seed(e))),
    ev_set_va(e, va), ctx, cfg, n)

def event(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
          ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
          ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
          p: A.Pop<G>, +e: Ev, +ctx: P, +cfg: Config, +n: U32) -> Run<G>:
  ev.s1a(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness,
    tournament(~G, p, True{}, cfg_tsize(cfg), n, ev_bi(e), n, ev_seed(e)),
    e, ctx, cfg, n)

# ----------------------------------------------------------------
# GERAÇÃO E EVOLUÇÃO
# ----------------------------------------------------------------

def gen.go(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
           ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
           ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
           k: Nat, run: Run<G>, +ctx: P, +cfg: Config, +n: U32) -> Run<G>:
  match k:
    case 0n:
      run
    case 1n+q:
      match run:
        case Run{pop, +bi, +bf, +seed}:
          gen.go(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness, q,
            event(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness,
                  pop, Ev{n, n, bi, bf, seed}, ctx, cfg, n),
            ctx, cfg, n)

# Uma geração: `n/2` eventos, logo `n` filhos.
def generation(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
               ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
               ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
               run: Run<G>, +ctx: P, +cfg: Config, +n: U32) -> Run<G>:
  gen.go(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness, U32.to_nat(U32.shr(n)), run, ctx, cfg, n)

def evolve(~G: Type, ~P: Data, ~copy_into: @+c: P -> G -> G -> (G & G),
           ~crossover: @+c: P -> G -> G -> @+s: U32 -> (G & G),
           ~mutate: @+c: P -> G -> @+r: U32 -> @+s: U32 -> G, ~fitness: @+c: P -> G -> (G & U32),
           k: Nat, run: Run<G>, +ctx: P, +cfg: Config, +n: U32) -> Run<G>:
  match k:
    case 0n:
      run
    case 1n+q:
      evolve(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness, q,
        generation(~G, ~P, ~copy_into, ~crossover, ~mutate, ~fitness, run, ctx, cfg, n),
        ctx, cfg, n)

# ----------------------------------------------------------------
# COMEÇO E FIM
# ----------------------------------------------------------------

# A primeira avaliação, que dá o melhor inicial
def start.fin2(~G: Type, p: A.Pop<G>, best: U32 & U32, +seed: U32) -> Run<G>:
  (+bi, +bf) = best
  Run{p, bi, bf, seed}

def start.fin(~G: Type, r: A.Pop<G> & (U32 & U32), +seed: U32) -> Run<G>:
  (p, best) = r
  start.fin2(~G, p, best, seed)

def start(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
          p: A.Pop<G>, +ctx: P, +seed: U32) -> Run<G>:
  start.fin(~G, A.evaluate(~G, ~P, ~fitness, p, ctx), seed)

# O melhor da corrida, sem consumir o estado
def best_of(~G: Type, run: Run<G>) -> Run<G> & U32:
  match run:
    case Run{pop, +bi, +bf, +seed}:
      (Run{pop, bi, bf, seed}, bf)
