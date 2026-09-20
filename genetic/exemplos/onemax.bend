import Base
import ./../arena.bend as A
import ./../operators.bend as Op
import ./../ga.bend as GA
import ./../../utils/arrays.bend as Arr
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOU

# ================================================================
# ONEMAX — o problema mais simples que existe
# ================================================================
# Genoma: `Array<U32>` de `n` bits (cada gene é 0 ou 1).
# Aptidão: quantos bits são 1, mais 1 (0 é reservado para "não avaliado").
#
# É o teste de que a interface do problema é simples: são cinco funções
# pequenas, e nenhuma delas sabe que existe arena, buraco ou tupla.

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
def alloc(+ctx: Ctx) -> Array<U32>:
  match ctx:
    case Ctx{genes, +depth, rate}:
      Array.new(U32, depth, 0)

# init: preenche o genoma que já existe com bits aleatórios
def init_gene(v: U32, +seed: U32, i: U32) -> U32:
  U32.and(R.hash32((seed + i : U32)), 1)

def init(+ctx: Ctx, g: Array<U32>, +seed: U32) -> Array<U32>:
  Arr.for_each(~U32, ~U32, ~init_gene, g, seed)

# hash do genoma (polinomial), para o diversity check
def hash_gene(+x: U32, acc: U32, i: U32) -> U32:
  (U32.mul(acc, 31) + x : U32)

def hash(+ctx: Ctx, g: Array<U32>) -> Array<U32> & U32:
  Arr.reduce(~U32, ~U32, ~hash_gene, g, 7)

# fitness: soma dos bits + 1
def count_bit(+x: U32, acc: U32, i: U32) -> U32:
  (acc + x : U32)

def fitness.fin(r: Array<U32> & U32) -> Array<U32> & U32:
  (g, +s) = r
  (g, U32.inc(s))

def fitness(+ctx: Ctx, g: Array<U32>) -> Array<U32> & U32:
  fitness.fin(Arr.reduce(~U32, ~U32, ~count_bit, g, 0))

# mutação: troca bits com taxa por gene (salto geométrico)
def mutate(+ctx: Ctx, g: Array<U32>, +rate: U32, +seed: U32) -> Array<U32>:
  Op.mut_replace(g, ctx_genes(ctx), 2, rate, seed)

# cruzamento: um ponto, in-place nos dois genomas (que já são os filhos)
def crossover(+ctx: Ctx, a: Array<U32>, b: Array<U32>, +seed: U32) -> Array<U32> & Array<U32>:
  Op.cross_1point(a, b, ctx_genes(ctx), seed)

# cópia: o motor usa isto para o filho nascer com os genes do pai
def copy_into(+ctx: Ctx, dst: Array<U32>, src: Array<U32>) -> Array<U32> & Array<U32>:
  Arr.copy_range(~U32, dst, src, 0, ctx_genes(ctx))

# ----------------------------------------------------------------
# main
# ARGS: log2(genes) log2(pop) gerações semente log2(demes) época diversidade(0/1) max_stag
# ----------------------------------------------------------------

def relato(r: (GA.Run<Array<U32>> & Array<U32>) & U32, +genes: U32, +pop: U32, +gens: U32, +demes: U32) -> String:
  (st, +bf) = r
  "genes=" ++ U32.show(genes) ++ " pop=" ++ U32.show(pop) ++ " demes=" ++ U32.show(demes) ++
  " gerações=" ++ U32.show(gens) ++ " | melhor: " ++ U32.show((bf - 1 : U32)) ++ "/" ++ U32.show(genes) ++
  Bool.pick(String, U32.is_eq((bf - 1 : U32), genes), "  (ÓTIMO)", "")

def run(+genes_d: U32, +pop_d: U32, +gens: U32, +seed: U32, +demes_d: U32, +epoca: U32, +div: U32, +max_stag: U32) -> String:
  +ctx = ctx_new(genes_d, R.per(1, U32.shln(1, U32.to_nat(genes_d))))
  +n = U32.shln(1, U32.to_nat(pop_d))
  # mesma configuração do teste do Rust: 90% de cruzamento, 90% de mutação,
  # taxa por gene 1/N, torneio de 5
  +cfg = GA.cfg_new(R.per(9, 10), R.per(9, 10), R.per(1, ctx_genes(ctx)), 5, U32.is_ne(div, 0), max_stag)
  relato(
    GA.best_st(~Array<U32>,
      GA.archipelago(~Array<U32>, ~Ctx, ~alloc, ~init, ~copy_into, ~crossover, ~mutate, ~fitness, ~hash,
        U32.to_nat(U32.max(U32.div(gens, U32.max(epoca, 1)), 1)), U32.to_nat(demes_d),
        GA.start_st(~Array<U32>, ~Ctx, ~fitness,
          A.pop_new(~Array<U32>, ~Ctx, ~alloc, ~init, U32.to_nat(pop_d), ctx, seed), ctx, R.step(seed)),
        ctx, cfg, U32.max(epoca, 1), n)),
    ctx_genes(ctx), n, gens, U32.shln(1, U32.to_nat(demes_d)))

def go(args: List<String>) -> IO(Unit):
  +nums = IOU.numbers(args)
  IO.print(run(IOU.num_at(nums, 0n, 7), IOU.num_at(nums, 1n, 6), IOU.num_at(nums, 2n, 100),
               IOU.num_at(nums, 3n, 12345), IOU.num_at(nums, 4n, 0), IOU.num_at(nums, 5n, 10),
               IOU.num_at(nums, 6n, 0), IOU.num_at(nums, 7n, 0)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), go)
