import Base
import ./ga.bend as GA
import ./utils/perm.bend as Perm
import ./utils/random.bend as R

# ================================================================
# BENCHMARK DE PARALELISMO COARSE-GRAINED (PGA VIA MOTOR GENÉRICO)
# ================================================================
# Teste de alta densidade computacional para avaliar escala multicore.
# Usa o motor genérico ga.bend sobre a topologia de 8 ilhas paralelas.
# ================================================================

def city_dist(+c1: U32, +c2: U32) -> U32:
  +d = Bool.pick(U32, U32.is_ge(c1, c2), (c1 - c2 : U32), (c2 - c1 : U32))
  (d * 10 : U32)

def tour_distance(+p: Perm.Perm8) -> U32:
  +c0 = Perm.Perm8.get(p, 0); +c1 = Perm.Perm8.get(p, 1)
  +c2 = Perm.Perm8.get(p, 2); +c3 = Perm.Perm8.get(p, 3)
  +c4 = Perm.Perm8.get(p, 4); +c5 = Perm.Perm8.get(p, 5)
  +c6 = Perm.Perm8.get(p, 6); +c7 = Perm.Perm8.get(p, 7)
  (city_dist(c0, c1) + city_dist(c1, c2) + city_dist(c2, c3) + city_dist(c3, c4) +
   city_dist(c4, c5) + city_dist(c5, c6) + city_dist(c6, c7) + city_dist(c7, c0) : U32)

def fitness(p: Perm.Perm8) -> U32:
  +d = tour_distance(p)
  Bool.pick(U32, U32.is_gt(d, 1000), 0, (1000 - d : U32))

def init_gene(seed: U32) -> Perm.Perm8:
  Perm.make_perm8(0, 1, 2, 3, 4, 5, 6, 7)

def mutate_tour(+p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  +s1 = R.step(s)
  +s2 = R.step(s1)
  Perm.Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))

def reproduce(parent: Perm.Perm8, champ: Perm.Perm8, seed: U32) -> Perm.Perm8:
  +s1 = R.step(seed)
  +s2 = R.step(s1)
  +base = Bool.pick(Perm.Perm8, U32.is_lt(U32.mod(s1, 10), 6), champ, parent)
  mutate_tour(base, s2)

def main() -> IO(Unit):
  +s0 = {12345678 : U32}
  # 8 Ilhas x 32 indivíduos = 256 indivíduos
  +arch0 = GA.gen_archipelago(~Perm.Perm8, ~init_gene, ~fitness, 3n, s0, 5n)
  # 20 épocas x 250 gerações = 5.000 gerações totais por ilha
  +arch_fin = GA.run_archipelago(~Perm.Perm8, ~reproduce, ~fitness, 20n, arch0, R.step(s0), 250n)
  +champ_fin = GA.best_archipelago(Perm.Perm8, arch_fin)
  +d_fin = tour_distance(GA.Ind.gene(Perm.Perm8, champ_fin))
  IO.print("PGA Benchmark (8 Ilhas) - Distancia Campeao: " ++ U32.show(d_fin) ++ "\n")
