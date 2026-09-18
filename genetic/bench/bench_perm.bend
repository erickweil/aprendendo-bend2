import Base
import ./../ga.bend as GA
import ./../operators.bend as Op
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R

# ================================================================
# BENCHMARK: CARGA PESADA SOBRE PERMUTACOES (TSP / OX1)
# ================================================================
# 8 ilhas x 64 individuos x 20 epocas x 250 geracoes = 2.560.000
# reproducoes, cada uma com Order Crossover + mutacao combinada.
# Exercita o caminho quente de operators.bend Secao C.
# ================================================================

def city_dist(+c1: U32, +c2: U32) -> U32:
  +d = Bool.pick(U32, U32.is_ge(c1, c2), (c1 - c2 : U32), (c2 - c1 : U32))
  (d * 10 : U32)

def tour_distance(p: Perm.Perm8) -> U32:
  Perm.P8{c0, c1, c2, c3, c4, c5, c6, c7} = p
  +c0 = c0; +c1 = c1; +c2 = c2; +c3 = c3
  +c4 = c4; +c5 = c5; +c6 = c6; +c7 = c7
  (city_dist(c0, c1) + city_dist(c1, c2) + city_dist(c2, c3) + city_dist(c3, c4) +
   city_dist(c4, c5) + city_dist(c5, c6) + city_dist(c6, c7) + city_dist(c7, c0) : U32)

def fitness(p: Perm.Perm8) -> U32:
  +d = tour_distance(p)
  Bool.pick(U32, U32.is_gt(d, 1000), 0, (1000 - d : U32))

def init_gene(seed: U32) -> Perm.Perm8:
  Op.mut_perm_random_swap(Perm.P8{0, 1, 2, 3, 4, 5, 6, 7}, seed)

def mut_tsp(p: Perm.Perm8, seed: U32) -> Perm.Perm8:
  Op.combine_mutations(~Perm.Perm8, ~Op.mut_perm_random_swap, ~Op.mut_perm_reverse_segment,
                       50, p, seed)

def reproduce(parent: Perm.Perm8, champ: Perm.Perm8, seed: U32) -> Perm.Perm8:
  Op.pipe(~Perm.Perm8, ~Op.cross_perm_ox1, ~mut_tsp, parent, champ, seed)

def main() -> IO(Unit):
  +s0 = {12345678 : U32}
  +arch0 = GA.gen_archipelago(~Perm.Perm8, ~init_gene, ~fitness, 3n, s0, 6n)
  +arch_fin = GA.run_archipelago(~Perm.Perm8, ~reproduce, ~fitness, 20n, arch0, R.step(s0), 250n)
  +champ = GA.best_archipelago(Perm.Perm8, arch_fin)
  IO.print("bench_perm | distancia campea: " ++ U32.show(tour_distance(GA.Ind.gene(Perm.Perm8, champ))) ++ "\n")
