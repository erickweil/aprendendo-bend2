import Base
import ./../../utils/random.bend as R
import ./../utils/genes.bend as V
import ./../operators.bend as Op
import ./../mutations.bend as M
import ./../ga.bend as GA
import ./../../utils/io.bend as IOHelper

# ================================================================
# CENÁRIO 2: ORDENAÇÃO POR ALGORITMO GENÉTICO (sorting.bend)
# ================================================================
# Problema: dada uma lista de números, encontrar a PERMUTAÇÃO que os coloca
# em ordem crescente. O genoma não é a lista ordenada — é a ordem de leitura.
#
# É o exemplo mais simples de genoma-permutação, e serve para mostrar por que
# ele precisa de operadores próprios: um cruzamento posicional (uniforme, 1 ou
# 2 pontos) misturaria índices repetidos e destruiria a permutação. O operador
# correto é o Order Crossover (OX1), e as mutações são trocas de posição, que
# por construção preservam o multiconjunto de genes.
#
# Genoma...: permutação de [0, N-1]
# Aptidão..: número de pares vizinhos já em ordem crescente (máximo N-1)
# Seleção..: torneio de 4
# ================================================================

def N() -> U32:
  12

# A lista a ordenar
def vals() -> List<&2, U32>:
  [42, 7, 19, 3, 88, 25, 61, 14, 50, 33, 96, 8]

# ----------------------------------------------------------------
# PROBLEMA
# ----------------------------------------------------------------

# Genoma inicial: a identidade embaralhada por transposições aleatórias
def init_gene(seed: U32) -> List<&2, U32>:
  V.perm_random(N(), seed)

# Aplica a permutação: lê `vals` na ordem que o genoma manda
def apply_perm(perm: List<&2, U32>) -> List<&2, U32>:
  match perm:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      Con{V.nth(U32, vals(), i, 0), apply_perm(t)}

# Quantos elementos DEPOIS de `x` são maiores ou iguais a ele
def count_ordered(l: List<&2, U32>, +x: U32, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{h, t}:
      count_ordered(t, x, (acc + Bool.pick(U32, U32.is_le(x, h), 1, 0) : U32))

# Pares (i, j) com i < j já na ordem certa. É o complemento do número de
# inversões, e dá um gradiente MUITO melhor que contar vizinhos em ordem:
# trocar dois elementos distantes muda a aptidão em proporção à distância,
# então o GA enxerga progresso parcial em vez de um platô.
def ordered_pairs(l: List<&2, U32>) -> U32:
  match l:
    case Nil{}:
      0
    case Con{h, t}:
      +t = t
      (count_ordered(t, h, 0) + ordered_pairs(t) : U32)

# Máximo: N*(N-1)/2 pares
def max_fitness() -> U32:
  (U32.div((N() * (N() - 1 : U32) : U32), 2) : U32)

def fitness(gene: List<&2, U32>) -> U32:
  ordered_pairs(apply_perm(gene))

# Reprodução: OX1 seguido de duas mutações de troca com sementes independentes
# Chave do OX1: o gene de uma permutação de [0, N) já é o próprio índice
def key(g: U32) -> U32:
  g

def reproduce(p1: List<&2, U32>, p2: List<&2, U32>, seed: U32) -> List<&2, U32>:
  +seed = seed
  +s1 = R.split.fst(seed)
  +s2 = R.split.snd(seed)
  +child = Op.cross_ox1(~U32, ~key, p1, p2, N(), seed)
  M.mut_neighbor(U32, M.mut_swap(~U32, child, N(), R.per(1, 20), s1), N(), R.per(1, 10), s2)

# ----------------------------------------------------------------
# SAÍDA
# ----------------------------------------------------------------

def show_list(l: List<&2, U32>) -> String:
  match l:
    case Nil{}:
      ""
    case Con{h, t}:
      U32.show(h) ++ " " ++ show_list(t)

def run(args: List<String>) -> IO(Unit):
  +s0 = IOHelper.arg_u32(args, 20260918)
  # 64 indivíduos (profundidade 6)
  +g0 = GA.first_gen(~List<&2, U32>, ~init_gene, ~fitness, 6n, s0)
  +g0 = g0
  +f0 = GA.Gen.bfit(List<&2, U32>, g0)

  +gf = GA.run_gen_loop_tourney(~List<&2, U32>, ~reproduce, ~fitness, 120n, g0, R.step(s0), 4n)
  +best = GA.Gen.best(List<&2, U32>, gf)
  +ff = GA.Ind.fit(List<&2, U32>, best)
  +gene = GA.Ind.gene(List<&2, U32>, best)

  IO.print(
    "=== CENÁRIO 2: ORDENAÇÃO (genoma-permutação) ===\n" ++
    "Entrada..............: " ++ show_list(vals()) ++ "\n" ++
    "População............: 64 indivíduos, torneio de 4, 120 gerações\n" ++
    "Aptidão máxima.......: " ++ U32.show(max_fitness()) ++ " pares em ordem\n" ++
    "Geração 0............: " ++ U32.show(f0) ++ "\n" ++
    "Geração 120..........: " ++ U32.show(ff) ++ "\n" ++
    "Permutação encontrada: " ++ show_list(gene) ++ "\n" ++
    "Saída ordenada.......: " ++ show_list(apply_perm(gene)) ++ "\n" ++
    "Ordenou?.............: " ++ Bool.show(U32.is_eq(ff, max_fitness())) ++ "\n"
  )

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
