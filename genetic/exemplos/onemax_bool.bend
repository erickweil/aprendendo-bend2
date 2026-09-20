import Base
import ./../arena.bend as A
import ./../operators.bend as Op
import ./../ga.bend as GA
import ./../../utils/arrays.bend as Arr
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOU

# ================================================================
# ONEMAX BOOL — OneMax usando Array<Bool>
# ================================================================
# Genoma: `Array<Bool>` de `n` bits (True{} ou False{}).
# Aptidão: quantos bits são True{}, mais 1 (0 é reservado para "não avaliado").
#
# Equivalente ao modelo do Rust (Vec<bool>), onde cada gene é um booleano.

# O contexto do problema: `Data`, read-only, duplicável à vontade.
# `depth` é o log2 de `genes` (o Array tem 2^depth posições).
type Ctx is Data:
  Ctx{genes: U32, depth: Nat, mut_rate: U32}

def ctx_new(+genes_d: U32, +rate: U32) -> Ctx:
  Ctx{U32.shln(1, U32.to_nat(genes_d)), U32.to_nat(genes_d), rate}

def ctx_genes(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{+genes, depth, rate}:
      genes

# ----------------------------------------------------------------
# A interface do problema
# ----------------------------------------------------------------

# alloc: o ÚNICO ponto de alocação de genoma do motor
def alloc(+ctx: Ctx) -> Array<Bool>:
  match ctx:
    case Ctx{genes, +depth, rate}:
      Array.new(Bool, depth, False{})

# init: preenche o genoma que já existe com booleanos aleatórios
def init_gene(v: Bool, +seed: U32, i: U32) -> Bool:
  U32.is_ne(U32.and(R.hash32((seed + i : U32)), 1), 0)

def init(+ctx: Ctx, g: Array<Bool>, +seed: U32) -> Array<Bool>:
  Arr.for_each(~Bool, ~U32, ~init_gene, g, seed)

# hash do genoma (polinomial), para o diversity check
def hash_gene(+x: Bool, acc: U32, i: U32) -> U32:
  (U32.mul(acc, 31) + Bool.to_u32(x) : U32)

def hash(+ctx: Ctx, g: Array<Bool>) -> Array<Bool> & U32:
  Arr.reduce(~Bool, ~U32, ~hash_gene, g, 7)

# fitness: soma dos bits True{} + 1
def count_bit(+x: Bool, acc: U32, i: U32) -> U32:
  (acc + Bool.to_u32(x) : U32)

def fitness.fin(r: Array<Bool> & U32) -> Array<Bool> & U32:
  (g, +s) = r
  (g, U32.inc(s))

def fitness(+ctx: Ctx, g: Array<Bool>) -> Array<Bool> & U32:
  fitness.fin(Arr.reduce(~Bool, ~U32, ~count_bit, g, 0))

# ----------------------------------------------------------------
# Operadores para Array<Bool>
# ----------------------------------------------------------------

def bool_flip(b: Bool) -> Bool:
  match b:
    case True{}: False{}
    case False{}: True{}

def mut_bool.flip(r: Array<Bool> & Bool, +i: U32) -> Array<Bool>:
  (arr, b) = r
  Array.set(Bool, arr, i, bool_flip(b))

def mut_bool.go(fuel: Nat, stop: Bool, g: Array<Bool>, +i: U32, +n: U32,
                +rate: U32, +lnq: F32, +seed: U32) -> Array<Bool>:
  match fuel stop:
    case _ True{}:
      g
    case 0n False{}:
      g
    case 1n+p False{}:
      +jump = U32.inc(R.gap(R.split.fst(seed), rate, lnq))
      +j = (i + jump : U32)
      mut_bool.go(p, U32.is_ge(j, n),
        mut_bool.flip(Array.get(Bool, g, i), i),
        j, n, rate, lnq, R.step(seed))

# Mutação: inverte o bit nos genes sorteados pelo salto geométrico (idêntico ao Rust)
def mut_bool(g: Array<Bool>, +n: U32, +rate: U32, +seed: U32) -> Array<Bool>:
  +lnq = R.ln_miss(rate)
  +first = R.gap(seed, rate, lnq)
  mut_bool.go(U32.to_nat(n), U32.is_ge(first, n), g, first, n, rate, lnq, R.step(seed))

def mutate(+ctx: Ctx, g: Array<Bool>, +rate: U32, +seed: U32) -> Array<Bool>:
  mut_bool(g, ctx_genes(ctx), rate, seed)

# Crossover de 1 ponto para Array<Bool>
def cross_1point_bool(a: Array<Bool>, b: Array<Bool>, +n: U32, +seed: U32) -> Array<Bool> & Array<Bool>:
  +cut = U32.inc(R.range(seed, U32.max((n - 1 : U32), 1)))
  Arr.swap_range(~Bool, a, b, cut, (n - cut : U32))

# Cópia in-place entre buffers de Array<Bool>
# "4 ENTRAM, 4 SAEM" COM FITNESS FUNDIDO: lê os dois pais, escreve os dois
# filhos e conta os bits no mesmo laço. O motor não faz passada de avaliação.
# O `~U32.inc` no fim garante que a aptidão nunca é 0 (a marca de "não avaliado").
# "4 ENTRAM, 4 SAEM": lê os dois pais (da geração atual) e escreve os dois
# filhos (na próxima) numa varredura só. `cruza = False{}` vira corte = n, que
# é cópia pura. A aptidão é etapa separada, depois da mutação.
def breed(+ctx: Ctx, ca: Array<Bool>, cb: Array<Bool>, pa: Array<Bool>, pb: Array<Bool>,
          cruza: Bool, +seed: U32) -> (Array<Bool> & Array<Bool>) & (Array<Bool> & Array<Bool>):
  Op.breed_1point(~Bool, ca, cb, pa, pb, ctx_genes(ctx), cruza, seed)

# ----------------------------------------------------------------
# main
# ARGS: log2(genes) log2(pop) gerações semente log2(demes) época diversidade(0/1) max_stag
# ----------------------------------------------------------------

def relato(r: (GA.Run<Array<Bool>> & Array<U32>) & U32, +genes: U32, +pop: U32, +gens: U32, +demes: U32) -> String:
  (st, +bf) = r
  "genes=" ++ U32.show(genes) ++ " pop=" ++ U32.show(pop) ++ " demes=" ++ U32.show(demes) ++
  " gerações=" ++ U32.show(gens) ++ " | melhor: " ++ U32.show((bf - 1 : U32)) ++ "/" ++ U32.show(genes) ++
  Bool.pick(String, U32.is_eq((bf - 1 : U32), genes), "  (ÓTIMO)", "")

def run(+genes_d: U32, +pop_d: U32, +gens: U32, +seed: U32, +demes_d: U32, +epoca: U32, +div: U32, +max_stag: U32) -> String:
  +ctx = ctx_new(genes_d, R.per(1, U32.shln(1, U32.to_nat(genes_d))))
  +n = U32.shln(1, U32.to_nat(pop_d))
  +cfg = GA.cfg_new(R.per(9, 10), R.per(9, 10), R.per(1, ctx_genes(ctx)), 5, U32.is_ne(div, 0), max_stag)
  relato(
    GA.best_st(~Array<Bool>,
      GA.archipelago(~Array<Bool>, ~Ctx, ~alloc, ~init, ~breed, ~mutate, ~fitness, ~hash,
        U32.to_nat(U32.max(U32.div(gens, U32.max(epoca, 1)), 1)), U32.to_nat(demes_d),
        GA.start_st(~Array<Bool>, ~Ctx, ~fitness,
          A.pop_new(~Array<Bool>, ~Ctx, ~alloc, ~init, U32.to_nat(pop_d), ctx, seed), ctx, R.step(seed)),
        ctx, cfg, U32.max(epoca, 1), n)),
    ctx_genes(ctx), n, gens, U32.shln(1, U32.to_nat(demes_d)))

def go(args: List<String>) -> IO(Unit):
  +nums = IOU.numbers(args)
  IO.print(run(IOU.num_at(nums, 0n, 7), IOU.num_at(nums, 1n, 6), IOU.num_at(nums, 2n, 100),
               IOU.num_at(nums, 3n, 12345), IOU.num_at(nums, 4n, 0), IOU.num_at(nums, 5n, 10),
               IOU.num_at(nums, 6n, 0), IOU.num_at(nums, 7n, 0)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), go)