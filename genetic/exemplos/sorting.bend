import Base
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOHelper
import ./../utils/genes.bend as V
import ./../operators.bend as Op
import ./../mutations.bend as M
import ./../ga.bend as GA

# ================================================================
# CENÁRIO 2: ORDENAÇÃO POR ALGORITMO GENÉTICO (sorting.bend)
# ================================================================
# Problema: dada uma lista de números, encontrar a PERMUTAÇÃO que os coloca
# em ordem crescente. O genoma não é a lista ordenada — é a ordem de leitura.
#
# É o exemplo mais simples de genoma-permutação, e mostra por que ele precisa
# de operadores próprios: um cruzamento posicional misturaria índices
# repetidos. O correto é o Order Crossover (OX1), e as mutações são trocas,
# que preservam a permutação por construção.
#
# Contexto...: a lista a ordenar e seu tamanho (o `&self` do Rust)
# Genoma.....: permutação de [0, N-1]
# Aptidão....: pares (i, j), i < j, já em ordem (máximo N(N-1)/2)
#
# Uso: bend sorting.bend [SEMENTE] [N]
#      sem N ordena a lista fixa de 12 números; com N, N números aleatórios
# ================================================================

type Sort is Data:
  Sort{vals: List<&2, U32>, n: U32}

def Sort.vals(s: Sort) -> List<&2, U32>:
  Sort{v, _} = s
  v

def Sort.n(s: Sort) -> U32:
  Sort{_, n} = s
  n

def fixed() -> List<&2, U32>:
  [42, 7, 19, 3, 88, 25, 61, 14, 50, 33, 96, 8]

def random_vals(k: Nat, +seed: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{U32.mod(R.mix(seed), 1000), random_vals(p, R.step(seed))}

# ----------------------------------------------------------------
# PROBLEMA
# ----------------------------------------------------------------

def init_gene(ctx: Sort, seed: U32) -> List<&2, U32>:
  V.perm_random(Sort.n(ctx), seed)

# Lê os valores na ordem do genoma. Os valores viram um `Array` local, então
# cada leitura é O(1); o par (array, valor lido) é o estado do laço.
def apply.go(perm: List<&2, U32>, r: Array<U32> & U32) -> List<&2, U32>:
  match perm:
    case Nil{}:
      (a, v) = r
      Con{v, Nil{}}
    case Con{i, t}:
      (a, v) = r
      Con{v, apply.go(t, Array.get(U32, a, i))}

def apply_perm(+ctx: Sort, perm: List<&2, U32>) -> List<&2, U32>:
  match perm:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      apply.go(t, Array.get(U32, V.to_array(~U32, Sort.vals(ctx), Sort.n(ctx), 0), i))

# Quantos elementos DEPOIS de `x` são maiores ou iguais a ele
def count_ordered(l: List<&2, U32>, +x: U32, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{h, t}:
      count_ordered(t, x, (acc + Bool.to_u32(U32.is_le(x, h)) : U32))

# Pares (i, j) com i < j já na ordem certa: o complemento do número de
# inversões. Dá um gradiente muito melhor que contar vizinhos em ordem.
def ordered_pairs(l: List<&2, U32>) -> U32:
  match l:
    case Nil{}:
      0
    case Con{h, +t}:
      (count_ordered(t, h, 0) + ordered_pairs(t) : U32)

def max_fitness(+n: U32) -> U32:
  U32.div((n * (n - 1 : U32) : U32), 2)

def fitness(ctx: Sort, gene: List<&2, U32>) -> U32:
  ordered_pairs(apply_perm(ctx, gene))

# Chave do OX1: o gene de uma permutação de [0, N) já é o próprio índice
def key(g: U32) -> U32:
  g

def hash(ctx: Sort, g: List<&2, U32>) -> U32:
  V.hash_list(~U32, ~key, g, 7)

def cross(ctx: Sort, a: List<&2, U32>, b: List<&2, U32>, seed: U32) -> List<&2, U32>:
  +ctx = ctx
  +n = Sort.n(ctx)
  Op.cross_ox1(~U32, ~key, a, b, n, n, seed)

# Troca aleatória seguida de troca de vizinhos, com a taxa por gene do motor
def mutate(ctx: Sort, g: List<&2, U32>, rate: U32, seed: U32) -> List<&2, U32>:
  +ctx = ctx
  +n = Sort.n(ctx)
  +rate = rate
  +seed = seed
  M.mut_neighbor(U32, M.mut_swap(~U32, g, n, rate, R.split.fst(seed)), n, rate, R.split.snd(seed))

# ----------------------------------------------------------------
# SAÍDA
# ----------------------------------------------------------------

def show_list(l: List<&2, U32>) -> String:
  match l:
    case Nil{}:
      ""
    case Con{h, t}:
      U32.show(h) ++ " " ++ show_list(t)

def make_ctx(+n: U32, +seed: U32) -> Sort:
  Bool.pick(Sort, U32.is_zero(n), Sort{fixed(), 12}, Sort{random_vals(U32.to_nat(n), seed), n})

def run(args: List<String>) -> IO(Unit):
  +nums = IOHelper.numbers(args)
  +s0 = IOHelper.num_at(nums, 0n, 20260918)
  +ctx = make_ctx(IOHelper.num_at(nums, 1n, 0), R.split.fth(s0))
  +n = Sort.n(ctx)
  +maxf = max_fitness(n)
  # 90% cruzamento, 90% mutação, 1/N por gene, torneio de 4, reinício após
  # 200 gerações sem melhora; 64 indivíduos; para ao ordenar
  +cfg = GA.config(R.per(9, 10), R.per(9, 10), R.per(1, n), 4, 200, maxf, 6, 0)
  +isl = GA.new_island(~Sort, ~List<&2, U32>, ~init_gene, ~fitness, ctx, cfg, s0)
  +f0 = GA.Island.best_f(List<&2, U32>, isl)
  +fin = GA.run_island(~Sort, ~List<&2, U32>, ~init_gene, ~fitness, ~hash, ~cross, ~mutate, 5000n, isl, ctx, cfg, R.step(s0))
  +best = GA.Island.best(List<&2, U32>, fin)
  +ff = GA.Ind.fit(List<&2, U32>, best)
  +gene = GA.Ind.gene(List<&2, U32>, best)
  IO.print(
    "=== CENÁRIO 2: ORDENAÇÃO (genoma-permutação) ===\n" ++
    "Entrada..............: " ++ show_list(Sort.vals(ctx)) ++ "\n" ++
    "População............: 64 indivíduos, torneio de 4, até 5000 gerações\n" ++
    "Aptidão..............: " ++ U32.show(f0) ++ " -> " ++ U32.show(ff) ++ " / " ++ U32.show(maxf) ++ "\n" ++
    "Gerações.............: " ++ U32.show(GA.Island.generation(List<&2, U32>, fin)) ++ "\n" ++
    "Saída ordenada.......: " ++ show_list(apply_perm(ctx, gene)) ++ "\n" ++
    "Ordenou?.............: " ++ Bool.show(U32.is_eq(ff, maxf)) ++ "\n"
  )

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
