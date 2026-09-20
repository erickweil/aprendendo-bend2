import Base
import ./../arena.bend as A
import ./../operators.bend as Op
import ./../ga.bend as GA
import ./../../utils/arrays.bend as Arr
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOU

# ================================================================
# TRAP ENGANOSO (deceptive trap) — o caso difícil
# ================================================================
# O genoma é uma cadeia de bits dividida em blocos de 4. Cada bloco vale:
#
#   4, se os quatro bits são 1        <- o ótimo global
#   3 - (quantidade de bits 1)        <- o gradiente aponta para o lado ERRADO
#
# Ou seja: todo-zeros vale 3 por bloco e é um atrator; todo-uns vale 4 e é o
# ótimo. Um GA guloso cai no atrator e fica preso. É o benchmark clássico para
# medir se diversidade, ilhas e controle de estagnação estão fazendo alguma
# coisa — no OneMax nada disso aparece, porque lá o gradiente é honesto.
#
# Aptidão máxima = número de genes (4 por bloco de 4).

type Ctx is Data:
  Ctx{genes: U32, depth: Nat}

def ctx_new(+genes_d: U32) -> Ctx:
  Ctx{U32.shln(1, U32.to_nat(genes_d)), U32.to_nat(genes_d)}

def ctx_genes(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{+genes, depth}:
      genes

# ----------------------------------------------------------------
# A interface do problema
# ----------------------------------------------------------------

def alloc(+ctx: Ctx) -> Array<U32>:
  match ctx:
    case Ctx{genes, +depth}:
      Array.new(U32, depth, 0)

def init_gene(v: U32, +seed: U32, i: U32) -> U32:
  U32.and(R.hash32((seed + i : U32)), 1)

def init(+ctx: Ctx, g: Array<U32>, +seed: U32) -> Array<U32>:
  Arr.for_each(~U32, ~U32, ~init_gene, g, seed)

# valor de um bloco de 4 bits com `u` bits ligados
def bloco(+u: U32) -> U32:
  Bool.pick(U32, U32.is_eq(u, 4), 4, (3 - u : U32))

# O acumulador carrega DUAS coisas num U32: os três bits baixos são a soma
# parcial do bloco atual (0..4) e o resto é o total fechado.
def trap_gene(+x: U32, acc: U32, i: U32) -> U32:
  +a = acc
  +u = (U32.and(a, 7) + x : U32)
  +tot = U32.shrn(a, 3n)
  Bool.pick(U32, U32.is_eq(U32.and(i, 3), 3),
    U32.shln((tot + bloco(u) : U32), 3n),
    (U32.shln(tot, 3n) + u : U32))

def fitness.fin(r: Array<U32> & U32) -> Array<U32> & U32:
  (g, +a) = r
  (g, U32.inc(U32.shrn(a, 3n)))

def fitness(+ctx: Ctx, g: Array<U32>) -> Array<U32> & U32:
  fitness.fin(Arr.reduce(~U32, ~U32, ~trap_gene, g, 0))

def hash_gene(+x: U32, acc: U32, i: U32) -> U32:
  (U32.mul(acc, 31) + x : U32)

def hash(+ctx: Ctx, g: Array<U32>) -> Array<U32> & U32:
  Arr.reduce(~U32, ~U32, ~hash_gene, g, 7)

def mutate(+ctx: Ctx, g: Array<U32>, +rate: U32, +seed: U32) -> Array<U32>:
  Op.mut_replace(g, ctx_genes(ctx), 2, rate, seed)

# "4 ENTRAM, 4 SAEM": lê os dois pais e escreve os dois filhos numa varredura
# só. A aptidão é etapa separada, depois da mutação.
def breed(+ctx: Ctx, ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, pb: Array<U32>,
          cruza: Bool, +seed: U32) -> (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  Op.breed_1point(~U32, ca, cb, pa, pb, ctx_genes(ctx), cruza, seed)

# ----------------------------------------------------------------
# main
# ARGS: log2(genes) log2(pop) gerações semente log2(demes) época diversidade(0/1) max_stag
# ----------------------------------------------------------------

def relato(r: (GA.Run<Array<U32>> & Array<U32>) & U32, +genes: U32, +pop: U32, +demes: U32) -> String:
  (st, +bf) = r
  "genes=" ++ U32.show(genes) ++ " pop=" ++ U32.show(pop) ++ " demes=" ++ U32.show(demes) ++
  " | melhor: " ++ U32.show((bf - 1 : U32)) ++ "/" ++ U32.show(genes) ++
  Bool.pick(String, U32.is_eq((bf - 1 : U32), genes), "  (ÓTIMO)", "")

def run(+genes_d: U32, +pop_d: U32, +gens: U32, +seed: U32, +demes_d: U32, +epoca: U32,
        +div: U32, +max_stag: U32) -> String:
  +ctx = ctx_new(genes_d)
  +n = U32.shln(1, U32.to_nat(pop_d))
  +cfg = GA.cfg_new(R.per(9, 10), R.per(9, 10), R.per(1, ctx_genes(ctx)), 5,
                    U32.is_ne(div, 0), max_stag)
  relato(
    GA.best_st(~Array<U32>,
      GA.archipelago(~Array<U32>, ~Ctx, ~alloc, ~init, ~breed, ~mutate, ~fitness, ~hash,
        U32.to_nat(U32.max(U32.div(gens, U32.max(epoca, 1)), 1)), U32.to_nat(demes_d),
        GA.start_st(~Array<U32>, ~Ctx, ~fitness,
          A.pop_new(~Array<U32>, ~Ctx, ~alloc, ~init, U32.to_nat(pop_d), ctx, seed), ctx, R.step(seed)),
        ctx, cfg, U32.max(epoca, 1), n)),
    ctx_genes(ctx), n, U32.shln(1, U32.to_nat(demes_d)))

def go(args: List<String>) -> IO(Unit):
  +nums = IOU.numbers(args)
  IO.print(run(IOU.num_at(nums, 0n, 7), IOU.num_at(nums, 1n, 6), IOU.num_at(nums, 2n, 300),
               IOU.num_at(nums, 3n, 12345), IOU.num_at(nums, 4n, 0), IOU.num_at(nums, 5n, 10),
               IOU.num_at(nums, 6n, 0), IOU.num_at(nums, 7n, 0)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), go)
