import Base
import ./../ga.bend as GA
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R

# ================================================================
# CENÁRIO 3: CAIXEIRO VIAJANTE (TSP 8 CIDADES) COM MOTOR GENÉRICO
# ================================================================
# Problema: Encontrar o ciclo hamiltoniano de menor distância.
# Coordenadas em grade retangular: perímetro ótimo = 240.
# Fitness: (1000 - tour_distance). Ótimo = 760.
# ================================================================

# Coordenadas X e Y das 8 cidades
def city_x(+c: U32) -> U32:
  Bool.pick(U32, U32.is_lt(c, 4),
    Bool.pick(U32, U32.is_lt(c, 3), 20, 50),
    Bool.pick(U32, U32.is_eq(c, 7), 50, 80))

def city_y(+c: U32) -> U32:
  Bool.pick(U32, U32.is_lt(c, 4),
    Bool.pick(U32, U32.is_eq(c, 0), 20,
      Bool.pick(U32, U32.is_eq(c, 1), 50, 80)),
    Bool.pick(U32, U32.is_eq(c, 4), 80,
      Bool.pick(U32, U32.is_eq(c, 5), 50, 20)))

def abs_diff(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_ge(a, b), U32.sub(a, b), U32.sub(b, a))

def dist(+c1: U32, +c2: U32) -> U32:
  +dx = abs_diff(city_x(c1), city_x(c2))
  +dy = abs_diff(city_y(c1), city_y(c2))
  (dx + dy : U32)

def tour_distance(p: Perm.Perm8) -> U32:
  Perm.P8{c0, c1, c2, c3, c4, c5, c6, c7} = p
  +c0 = c0; +c1 = c1; +c2 = c2; +c3 = c3
  +c4 = c4; +c5 = c5; +c6 = c6; +c7 = c7

  +d0 = dist(c0, c1); +d1 = dist(c1, c2); +d2 = dist(c2, c3); +d3 = dist(c3, c4)
  +d4 = dist(c4, c5); +d5 = dist(c5, c6); +d6 = dist(c6, c7); +d7 = dist(c7, c0)
  (d0 + d1 + d2 + d3 + d4 + d5 + d6 + d7 : U32)

# Fitness = 1000 - tour_distance (ótimo = 1000 - 240 = 760)
def fitness(p: Perm.Perm8) -> U32:
  +d = tour_distance(p)
  (1000 - d : U32)

def shuffle_tour(+p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +p1 = Perm.Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))
  Perm.Perm8.swap(p1, U32.mod(s3, 8), U32.mod(s4, 8))

def init_gene(seed: U32) -> Perm.Perm8:
  shuffle_tour(Perm.P8{0, 4, 1, 5, 2, 6, 3, 7}, seed)

def mutate_tour(+p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  +s1 = R.step(s)
  +s2 = R.step(s1)
  Perm.Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))

# Reprodução: herdada da elite com mutação por permutação 2-opt
def reproduce(parent: Perm.Perm8, champ: Perm.Perm8, seed: U32) -> Perm.Perm8:
  +s1 = R.step(seed)
  +s2 = R.step(s1)
  +base = Bool.pick(Perm.Perm8, U32.is_lt(U32.mod(s1, 10), 6), champ, parent)
  mutate_tour(base, s2)

def main() -> IO(Unit):
  +s0 = {12345678 : U32}
  # População inicial: 16 indivíduos (árvore de profundidade 4)
  +pop0 = GA.gen_population(~Perm.Perm8, ~init_gene, ~fitness, 4n, s0)
  +best0 = GA.best_ind(Perm.Perm8, pop0)
  +g0 = GA.Ind.gene(Perm.Perm8, best0)
  +d0 = tour_distance(g0)

  # Evolução por 35 gerações com elitismo no motor ga.bend
  +pop_fin = GA.run_generations(~Perm.Perm8, ~reproduce, ~fitness, 35n, pop0, R.step(s0))
  +best_fin = GA.best_ind(Perm.Perm8, pop_fin)
  +g_fin = GA.Ind.gene(Perm.Perm8, best_fin)
  +d_fin = tour_distance(g_fin)

  IO.print(
    "=== CENÁRIO 3: CAIXEIRO VIAJANTE (TSP) ===\n" ++
    "População: 16 indivíduos (árvore binária profundidade 4)\n" ++
    "Geração 0 - Melhor Distância: " ++ U32.show(d0) ++ " | " ++ Perm.Perm8.show(g0) ++ "\n" ++
    "Geração 35 - Melhor Distância: " ++ U32.show(d_fin) ++ " | " ++ Perm.Perm8.show(g_fin) ++ "\n" ++
    "Distância Ótima Atingida (240)? " ++ Bool.show(U32.is_eq(d_fin, 240)) ++ "\n"
  )
