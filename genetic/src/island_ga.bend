import Base
import ./../ga.bend as GA
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R
import ./../operators.bend as Op

# ================================================================
# CENÁRIO PGA: MODELO DE ILHAS PARALELAS COM MOTOR GENÉTICO GENÉRICO
# ================================================================
# Arquipélago de 4 ilhas independentes x 16 indivíduos = 64 indivíduos.
# Cada ilha evolui isoladamente em um fluxo próprio (coarse-grained).
# A cada época, o campeão global migra para todas as ilhas.
# Toda a topologia de arquipélago, sincronização e migração é provida
# genericamente por genetic/ga.bend!
# ================================================================

# Coordenadas X e Y das 8 cidades (TSP)
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

def fitness(p: Perm.Perm8) -> U32:
  +d = tour_distance(p)
  (1000 - d : U32)

def shuffle_tour(+p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +p1 = Perm.Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))
  Perm.Perm8.swap(p1, U32.mod(s3, 8), U32.mod(s4, 8))

def init_gene(seed: U32) -> Perm.Perm8:
  shuffle_tour(Perm.P8{0, 4, 1, 5, 2, 6, 3, 7}, seed)

# Mutação de busca local: 60% inversão 2-opt de segmento + 40% swap de vizinho
def mut_island(p: Perm.Perm8, seed: U32) -> Perm.Perm8:
  Op.combine_mutations(~Perm.Perm8, ~Op.mut_perm_reverse_segment, ~Op.mut_perm_neighbor_swap,
                       60, p, seed)

# Reprodução por ilha: Order Crossover (OX1) + mutação 2-opt/vizinho,
# montada pelos combinadores higher-order de operators.bend
def reproduce(parent: Perm.Perm8, champ: Perm.Perm8, seed: U32) -> Perm.Perm8:
  Op.pipe(~Perm.Perm8, ~Op.cross_perm_ox1, ~mut_island, parent, champ, seed)

def main_seed() -> U32:
  654321

def main() -> IO(Unit):
  +s0 = main_seed()
  # 2^2 = 4 ilhas, cada uma com profundidade 4 = 16 indivíduos (64 indivíduos no total)
  +arch0 = GA.gen_archipelago(~Perm.Perm8, ~init_gene, ~fitness, 2n, s0, 4n)
  +champ0 = GA.best_archipelago(Perm.Perm8, arch0)
  +g0 = GA.Ind.gene(Perm.Perm8, champ0)
  +d0 = tour_distance(g0)

  # 5 épocas x 10 gerações = 50 gerações com migração periódica
  +arch_final = GA.run_archipelago(~Perm.Perm8, ~reproduce, ~fitness, 5n, arch0, R.step(s0), 10n)
  +champ_fin = GA.best_archipelago(Perm.Perm8, arch_final)
  +g_fin = GA.Ind.gene(Perm.Perm8, champ_fin)
  +d_fin = tour_distance(g_fin)

  IO.print(
    "=== MODELO DE ILHAS PARALELAS (PARALLEL ISLAND MODEL - PGA) ===\n" ++
    "Arquipélago: 4 Ilhas Independentes x 16 indivíduos = 64 indivíduos\n" ++
    "Paralelismo: Cada ilha evolui isoladamente em um fluxo próprio\n" ++
    "Migração: Campeão global migrado para todas as ilhas a cada 10 gerações\n" ++
    "Início    - Campeão Distância: " ++ U32.show(d0) ++ " | " ++ Perm.Perm8.show(g0) ++ "\n" ++
    "Final     - Campeão Distância: " ++ U32.show(d_fin) ++ " | " ++ Perm.Perm8.show(g_fin) ++ "\n" ++
    "Solução Ótima Alcançada no Arquipélago? " ++ Bool.show(U32.is_eq(d_fin, 240)) ++ "\n"
  )
