import Base
import ./../ga.bend as GA
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R

# ================================================================
# CENÁRIO 6: PROBLEMA DAS 8-RAINHAS (N-QUEENS) COM MOTOR GENÉRICO
# ================================================================
# Representação: Permutação de 8 inteiros (Perm8).
# Cada índice representa uma coluna, e o valor representa a linha.
# Linhas e colunas exclusivas por definição da permutação.
# Fitness: 100 - conflitos diagonais (Ótimo = 100, 0 conflitos).
# ================================================================

def abs_diff(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_ge(a, b), U32.sub(a, b), U32.sub(b, a))

# Conflito diagonal entre rainha em (r1, c1) e (r2, c2)
def diag_conflict(+c1: U32, +c2: U32, +dist_rows: U32) -> U32:
  Bool.pick(U32, U32.is_eq(abs_diff(c1, c2), dist_rows), 1, 0)

# Total de conflitos diagonais no tabuleiro 8x8
def queen_conflicts(p: Perm.Perm8) -> U32:
  Perm.P8{q0, q1, q2, q3, q4, q5, q6, q7} = p
  +q0 = q0; +q1 = q1; +q2 = q2; +q3 = q3
  +q4 = q4; +q5 = q5; +q6 = q6; +q7 = q7

  +c0 = (diag_conflict(q0, q1, 1) + diag_conflict(q0, q2, 2) + diag_conflict(q0, q3, 3) +
         diag_conflict(q0, q4, 4) + diag_conflict(q0, q5, 5) + diag_conflict(q0, q6, 6) + diag_conflict(q0, q7, 7) : U32)
  +c1 = (diag_conflict(q1, q2, 1) + diag_conflict(q1, q3, 2) + diag_conflict(q1, q4, 3) +
         diag_conflict(q1, q5, 4) + diag_conflict(q1, q6, 5) + diag_conflict(q1, q7, 6) : U32)
  +c2 = (diag_conflict(q2, q3, 1) + diag_conflict(q2, q4, 2) + diag_conflict(q2, q5, 3) +
         diag_conflict(q2, q6, 4) + diag_conflict(q2, q7, 5) : U32)
  +c3 = (diag_conflict(q3, q4, 1) + diag_conflict(q3, q5, 2) + diag_conflict(q3, q6, 3) + diag_conflict(q3, q7, 4) : U32)
  +c4 = (diag_conflict(q4, q5, 1) + diag_conflict(q4, q6, 2) + diag_conflict(q4, q7, 3) : U32)
  +c5 = (diag_conflict(q5, q6, 1) + diag_conflict(q5, q7, 2) : U32)
  +c6 = diag_conflict(q6, q7, 1)

  (c0 + c1 + c2 + c3 + c4 + c5 + c6 : U32)

# Fitness: 100 - conflitos (100 = 0 conflitos, solução perfeita)
def fitness(p: Perm.Perm8) -> U32:
  +c = queen_conflicts(p)
  (100 - c : U32)

def shuffle_queens(+p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +p1 = Perm.Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))
  Perm.Perm8.swap(p1, U32.mod(s3, 8), U32.mod(s4, 8))

def init_queens(seed: U32) -> Perm.Perm8:
  shuffle_queens(Perm.P8{0, 1, 2, 3, 4, 5, 6, 7}, seed)

def mutate_queens(+p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  +s1 = R.step(s); +s2 = R.step(s1)
  Perm.Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))

def reproduce(parent: Perm.Perm8, champ: Perm.Perm8, seed: U32) -> Perm.Perm8:
  +s1 = R.step(seed); +s2 = R.step(s1)
  +base = Bool.pick(Perm.Perm8, U32.is_zero(U32.and(s1, 1)), champ, parent)
  mutate_queens(base, s2)

def main_seed() -> U32:
  551122

def main() -> IO(Unit):
  +s0 = main_seed()
  # População inicial: 64 indivíduos (profundidade 6)
  +pop0 = GA.gen_population(~Perm.Perm8, ~init_queens, ~fitness, 6n, s0)
  +best0 = GA.best_ind(Perm.Perm8, pop0)
  +g0 = GA.Ind.gene(Perm.Perm8, best0)
  +f0 = GA.Ind.fit(Perm.Perm8, best0)
  +c0 = queen_conflicts(g0)

  # Evolução por 60 gerações com elitismo no motor ga.bend
  +pop_final = GA.run_generations(~Perm.Perm8, ~reproduce, ~fitness, 60n, pop0, R.step(s0))
  +best_fin = GA.best_ind(Perm.Perm8, pop_final)
  +g_fin = GA.Ind.gene(Perm.Perm8, best_fin)
  +f_fin = GA.Ind.fit(Perm.Perm8, best_fin)
  +c_fin = queen_conflicts(g_fin)

  IO.print(
    "=== CENÁRIO 6: PROBLEMA DAS 8-RAINHAS (N-QUEENS) ===\n" ++
    "Tabuleiro: 8x8 (Linhas e colunas exclusivas por permutação, minimiza diagonais)\n" ++
    "População: 64 indivíduos (árvore binária profundidade 6)\n" ++
    "Geração 0  - Conflitos Diagonais: " ++ U32.show(c0) ++ " (Fitness: " ++ U32.show(f0) ++ " / 100) | " ++ Perm.Perm8.show(g0) ++ "\n" ++
    "Geração 60 - Conflitos Diagonais: " ++ U32.show(c_fin) ++ " (Fitness: " ++ U32.show(f_fin) ++ " / 100) | " ++ Perm.Perm8.show(g_fin) ++ "\n" ++
    "Solução Ótima sem Conflitos? " ++ Bool.show(U32.is_zero(c_fin)) ++ "\n"
  )
