import Base
import ./../arena.bend as A
import ./../operators.bend as Op
import ./../../utils/arrays.bend as Arr
import ./../../utils/tuples.bend as T
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

# ----------------------------------------------------------------
# main: por enquanto monta a população, avalia e mostra o melhor.
# O laço de evolução entra quando o motor (ga.bend) estiver pronto.
# ARGS: log2(genes) log2(pop) semente
# ----------------------------------------------------------------

# (desestruturar a tupla de dentro exige a própria def: aninhar as duas
# desestruturações na mesma função não infere)
def relato.fin(best: U32 & U32, +genes: U32, +pop: U32) -> String:
  (+bi, +bf) = best
  "genes=" ++ U32.show(genes) ++ " pop=" ++ U32.show(pop) ++
  " | melhor inicial: slot " ++ U32.show(bi) ++ " com " ++ U32.show((bf - 1 : U32)) ++ "/" ++ U32.show(genes)

def relato(r: A.Pop<Array<U32>> & (U32 & U32), +genes: U32, +pop: U32) -> String:
  (p, best) = r
  relato.fin(best, genes, pop)

def run(+genes_d: U32, +pop_d: U32, +seed: U32) -> String:
  +ctx = ctx_new(genes_d, R.per(1, U32.shln(1, U32.to_nat(genes_d))))
  relato(
    A.evaluate(~Array<U32>, ~Ctx, ~fitness,
      A.pop_new(~Array<U32>, ~Ctx, ~alloc, ~init, U32.to_nat(pop_d), ctx, seed), ctx),
    ctx_genes(ctx), U32.shln(1, U32.to_nat(pop_d)))

def go(args: List<String>) -> IO(Unit):
  +nums = IOU.numbers(args)
  IO.print(run(IOU.num_at(nums, 0n, 10), IOU.num_at(nums, 1n, 6), IOU.num_at(nums, 2n, 12345)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), go)
