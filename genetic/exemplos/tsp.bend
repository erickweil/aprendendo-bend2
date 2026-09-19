import Base
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOHelper
import ./../utils/genes.bend as G
import ./../ga.bend as GA

# ================================================================
# CENÁRIO 3: CAIXEIRO VIAJANTE / TSP (tsp.bend)
# ================================================================
# Problema: visitar N cidades uma única vez e voltar à primeira, percorrendo
# a menor distância possível.
#
# Genoma...: permutação de [0, N-1] — a ordem de visita
# Aptidão..: BASE - distância*10 (o motor MAXIMIZA, então a distância entra
#            invertida; o fator 10 dá um degrau mais fino que o inteiro puro)
# Cruzam...: Order Crossover (OX1)
# Mutação..: troca aleatória + troca de vizinhos
# Seleção..: torneio de 5
#
# Esta instância é verificável: as 12 cidades estão sobre uma circunferência
# de raio 500. A rota ótima de qualquer conjunto de pontos sobre um círculo é
# o próprio polígono convexo, de comprimento 12 * 2 * 500 * sen(15°) ≈ 3106.
# A lista abaixo está embaralhada de propósito, para que a solução NÃO seja a
# permutação identidade.
# ================================================================

def N() -> U32:
  12

def OPTIMAL() -> U32:
  3106

def cx() -> List<&2, U32>:
  [0, 933, 250, 500, 933, 67, 1000, 250, 750, 67, 500, 750]

def cy() -> List<&2, U32>:
  [500, 750, 67, 1000, 250, 250, 500, 933, 67, 750, 0, 933]

# ----------------------------------------------------------------
# DISTÂNCIA
# ----------------------------------------------------------------

# Distância euclidiana entre as cidades `i` e `j`.
# Custa O(N) por causa do `nth` nas duas listas de coordenadas — com 12
# cidades é irrelevante, e evita guardar coordenadas dentro do genoma, que
# tem de continuar sendo só a permutação.
def dist(+i: U32, +j: U32) -> F32:
  +dx = (U32.to_f32(G.nth(U32, cx(), i, 0)) - U32.to_f32(G.nth(U32, cx(), j, 0)) : F32)
  +dy = (U32.to_f32(G.nth(U32, cy(), i, 0)) - U32.to_f32(G.nth(U32, cy(), j, 0)) : F32)
  F32.hypot(dx, dy)

# `first` desce a recursão inteira só para fechar o ciclo no caso base
def route_len.go(l: List<&2, U32>, +prev: U32, +first: U32, +acc: F32) -> F32:
  match l:
    case Nil{}:
      (acc + dist(prev, first) : F32)
    case Con{h, t}:
      +h = h
      route_len.go(t, h, first, (acc + dist(prev, h) : F32))

# Comprimento total do ciclo fechado descrito pela permutação
def route_len(l: List<&2, U32>) -> F32:
  match l:
    case Nil{}:
      {0.0 : F32}
    case Con{h, t}:
      +h = h
      route_len.go(t, h, h, {0.0 : F32})

def route_u32(l: List<&2, U32>) -> U32:
  F32.to_u32(route_len(l))

# ----------------------------------------------------------------
# PROBLEMA
# ----------------------------------------------------------------

def init_gene(seed: U32) -> List<&2, U32>:
  G.perm_shuffle(24n, G.perm_range(12n), N(), seed)

# O motor maximiza U32, então a distância entra subtraída de uma base grande
# o suficiente para nunca dar estouro por baixo.
def BASE() -> U32:
  1000000

def fitness(gene: List<&2, U32>) -> U32:
  (BASE() - F32.to_u32((route_len(gene) * {10.0 : F32} : F32)) : U32)

def fit_to_dist(+f: U32) -> U32:
  U32.div((BASE() - f : U32), 10)

def reproduce(p1: List<&2, U32>, p2: List<&2, U32>, seed: U32) -> List<&2, U32>:
  +seed = seed
  +s1 = R.split.fst(seed)
  +s2 = R.split.snd(seed)
  +child = G.cross_ox1(p1, p2, N(), seed)
  G.mut_neighbor(U32, G.mut_swap(U32, child, 60, N(), s1, 0), 10, s2)

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
  # 128 indivíduos (profundidade 7)
  +g0 = GA.first_gen(~List<&2, U32>, ~init_gene, ~fitness, 7n, s0)
  +g0 = g0
  +d0 = fit_to_dist(GA.Gen.bfit(List<&2, U32>, g0))

  +gf = GA.run_gen_loop_tourney(~List<&2, U32>, ~reproduce, ~fitness, 200n, g0, R.step(s0), 5n)
  +best = GA.Gen.best(List<&2, U32>, gf)
  +gene = GA.Ind.gene(List<&2, U32>, best)
  +gene = gene
  +df = route_u32(gene)

  IO.print(
    "=== CENÁRIO 3: CAIXEIRO VIAJANTE (12 cidades sobre um círculo) ===\n" ++
    "População........: 128 indivíduos, torneio de 5, 200 gerações\n" ++
    "Rota inicial.....: distância " ++ U32.show(d0) ++ "\n" ++
    "Rota final.......: " ++ show_list(gene) ++ "\n" ++
    "Distância final..: " ++ U32.show(df) ++ "\n" ++
    "Ótimo conhecido..: " ++ U32.show(OPTIMAL()) ++ " (o polígono convexo)\n" ++
    "Encontrou o ótimo: " ++ Bool.show(U32.is_le(df, OPTIMAL())) ++ "\n"
  )

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
