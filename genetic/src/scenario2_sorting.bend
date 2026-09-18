import Base
import ./../ga.bend as GA
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R
import ./../operators.bend as Op

# ================================================================
# CENÁRIO 2: ORDENAR NÚMEROS (SORTING) COM MOTOR GENÉTICO GENÉRICO
# ================================================================
# Problema: Encontrar a permutação ordenada [0, 1, 2, 3, 4, 5, 6, 7].
# Aptidão: Contagem de pares ordenados (xi <= xj para i < j). Máximo: 28.
# ================================================================

def pair_score(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_le(a, b), 1, 0)

# Fitness = contagem de pares ordenados. Max = 28.
def fitness(p: Perm.Perm8) -> U32:
  # assinatura afim, para casar com o tipo `G -> U32` esperado pelo motor
  +p = p
  +x0 = Perm.Perm8.get(p, 0); +x1 = Perm.Perm8.get(p, 1)
  +x2 = Perm.Perm8.get(p, 2); +x3 = Perm.Perm8.get(p, 3)
  +x4 = Perm.Perm8.get(p, 4); +x5 = Perm.Perm8.get(p, 5)
  +x6 = Perm.Perm8.get(p, 6); +x7 = Perm.Perm8.get(p, 7)

  +s0 = (pair_score(x0, x1) + pair_score(x0, x2) + pair_score(x0, x3) +
         pair_score(x0, x4) + pair_score(x0, x5) + pair_score(x0, x6) + pair_score(x0, x7) : U32)
  +s1 = (pair_score(x1, x2) + pair_score(x1, x3) + pair_score(x1, x4) +
         pair_score(x1, x5) + pair_score(x1, x6) + pair_score(x1, x7) : U32)
  +s2 = (pair_score(x2, x3) + pair_score(x2, x4) + pair_score(x2, x5) +
         pair_score(x2, x6) + pair_score(x2, x7) : U32)
  +s3 = (pair_score(x3, x4) + pair_score(x3, x5) + pair_score(x3, x6) + pair_score(x3, x7) : U32)
  +s4 = (pair_score(x4, x5) + pair_score(x4, x6) + pair_score(x4, x7) : U32)
  +s5 = (pair_score(x5, x6) + pair_score(x5, x7) : U32)
  +s6 = pair_score(x6, x7)

  (s0 + s1 + s2 + s3 + s4 + s5 + s6 : U32)

# Inicialização aleatória por embaralhamento
def shuffle(+p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +p1 = Perm.Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))
  Perm.Perm8.swap(p1, U32.mod(s3, 8), U32.mod(s4, 8))

def init_gene(seed: U32) -> Perm.Perm8:
  shuffle(Perm.make_perm8(0, 1, 2, 3, 4, 5, 6, 7), seed)

# Reprodução: PMX (Partially Mapped Crossover) + Swap de vizinho.
# O PMX preserva a sub-rota herdada do pai e resolve os conflitos por
# mapeamento inverso de posições, fechando sobre permutações válidas.
def reproduce(parent: Perm.Perm8, champ: Perm.Perm8, seed: U32) -> Perm.Perm8:
  Op.pipe(~Perm.Perm8, ~Op.cross_perm_pmx, ~Op.mut_perm_neighbor_swap, parent, champ, seed)

def main() -> IO(Unit):
  +s0 = {12345678 : U32}
  # População inicial: 16 indivíduos (árvore de profundidade 4)
  +pop0 = GA.gen_population(~Perm.Perm8, ~init_gene, ~fitness, 4n, s0)
  +best0 = GA.best_ind(Perm.Perm8, pop0)
  +f0 = GA.Ind.fit(Perm.Perm8, best0)
  +g0 = GA.Ind.gene(Perm.Perm8, best0)

  # Evolução por 30 gerações com elitismo no motor ga.bend
  +pop_fin = GA.run_generations(~Perm.Perm8, ~reproduce, ~fitness, 30n, pop0, R.step(s0))
  +best_fin = GA.best_ind(Perm.Perm8, pop_fin)
  +f_fin = GA.Ind.fit(Perm.Perm8, best_fin)
  +g_fin = GA.Ind.gene(Perm.Perm8, best_fin)

  IO.print(
    "=== CENÁRIO 2: ORDENAR NÚMEROS (NUMBER SORTING) ===\n" ++
    "População: 16 indivíduos (árvore binária profundidade 4)\n" ++
    "Geração 0 - Melhor Fitness: " ++ U32.show(f0) ++ " / 28 | " ++ Perm.Perm8.show(g0) ++ "\n" ++
    "Geração 30 - Melhor Fitness: " ++ U32.show(f_fin) ++ " / 28 | " ++ Perm.Perm8.show(g_fin) ++ "\n" ++
    "Ordenação Correta Atingida? " ++ Bool.show(U32.is_eq(f_fin, 28)) ++ "\n"
  )
