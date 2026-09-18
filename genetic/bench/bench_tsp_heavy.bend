import Base
import ./../ga.bend as GA
import ./../operators.bend as Op
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R
import ./../utils/math.bend as M

# ================================================================
# BENCHMARK: TSP COM AVALIACAO CARA (ABLACAO DE GRANULARIDADE)
# ================================================================
# Estrutura IDENTICA ao bench_perm (mesma alocacao por individuo,
# mesmos operadores), mas a aptidao usa distancia euclidiana real em
# F32 com raiz quadrada, ~20x mais computacao por individuo.
#
# Se a escala multicore melhorar aqui, o gargalo e' trafego de heap /
# memoria (diluido por mais computacao). Se nao melhorar, o gargalo e'
# granularidade de tarefa ou barreira.
# ================================================================

def city_x(+c: U32) -> F32:
  M.rnd_range_f32(U32.mul(U32.add(c, 1), 2654435761), {0.0 : F32}, {100.0 : F32})

def city_y(+c: U32) -> F32:
  M.rnd_range_f32(U32.mul(U32.add(c, 7), 2246822519), {0.0 : F32}, {100.0 : F32})

def euclid(+a: U32, +b: U32) -> F32:
  +dx = (city_x(a) - city_x(b) : F32)
  +dy = (city_y(a) - city_y(b) : F32)
  F32.sqrt(((dx * dx) + (dy * dy) : F32))

def tour_len(+p: Perm.Perm8) -> F32:
  +c0 = Perm.Perm8.get(p, 0); +c1 = Perm.Perm8.get(p, 1)
  +c2 = Perm.Perm8.get(p, 2); +c3 = Perm.Perm8.get(p, 3)
  +c4 = Perm.Perm8.get(p, 4); +c5 = Perm.Perm8.get(p, 5)
  +c6 = Perm.Perm8.get(p, 6); +c7 = Perm.Perm8.get(p, 7)
  (euclid(c0, c1) + euclid(c1, c2) + euclid(c2, c3) + euclid(c3, c4) +
   euclid(c4, c5) + euclid(c5, c6) + euclid(c6, c7) + euclid(c7, c0) : F32)

def fitness(p: Perm.Perm8) -> U32:
  +d = tour_len(p)
  Bool.pick(U32, F32.is_lt(d, {10000.0 : F32}),
    F32.to_u32(({10000.0 : F32} - d : F32)), 0)

def init_gene(seed: U32) -> Perm.Perm8:
  Op.mut_perm_random_swap(Perm.Perm8.identity(), seed)

def mut_tsp(p: Perm.Perm8, seed: U32) -> Perm.Perm8:
  Op.combine_mutations(~Perm.Perm8, ~Op.mut_perm_random_swap, ~Op.mut_perm_reverse_segment,
                       50, p, seed)

def reproduce(parent: Perm.Perm8, champ: Perm.Perm8, seed: U32) -> Perm.Perm8:
  Op.pipe(~Perm.Perm8, ~Op.cross_perm_ox1, ~mut_tsp, parent, champ, seed)

def main() -> IO(Unit):
  +s0 = {12345678 : U32}
  +arch0 = GA.gen_archipelago(~Perm.Perm8, ~init_gene, ~fitness, 2n, s0, 7n)
  +arch_fin = GA.run_archipelago(~Perm.Perm8, ~reproduce, ~fitness, 20n, arch0, R.step(s0), 250n)
  +champ = GA.best_archipelago(Perm.Perm8, arch_fin)
  IO.print("bench_tsp_heavy | rota: " ++ F32.show(tour_len(GA.Ind.gene(Perm.Perm8, champ))) ++ "\n")
