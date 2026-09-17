import Base

type Perm8 is Data:
  P8{x0: U32, x1: U32, x2: U32, x3: U32, x4: U32, x5: U32, x6: U32, x7: U32}

# Xorshift32 PRNG
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

def Perm8.get(p: Perm8, +idx: U32) -> U32:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  Bool.pick(U32, U32.is_lt(idx, 4),
    Bool.pick(U32, U32.is_lt(idx, 2),
      Bool.pick(U32, U32.is_eq(idx, 0), x0, x1),
      Bool.pick(U32, U32.is_eq(idx, 2), x2, x3)),
    Bool.pick(U32, U32.is_lt(idx, 6),
      Bool.pick(U32, U32.is_eq(idx, 4), x4, x5),
      Bool.pick(U32, U32.is_eq(idx, 6), x6, x7)))

def Perm8.set(p: Perm8, +idx: U32, +val: U32) -> Perm8:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  P8{
    Bool.pick(U32, U32.is_eq(idx, 0), val, x0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, x1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, x2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, x3),
    Bool.pick(U32, U32.is_eq(idx, 4), val, x4),
    Bool.pick(U32, U32.is_eq(idx, 5), val, x5),
    Bool.pick(U32, U32.is_eq(idx, 6), val, x6),
    Bool.pick(U32, U32.is_eq(idx, 7), val, x7)
  }

def Perm8.swap(+p: Perm8, +i: U32, +j: U32) -> Perm8:
  +vi = Perm8.get(p, i)
  +vj = Perm8.get(p, j)
  +p1 = Perm8.set(p, i, vj)
  Perm8.set(p1, j, vi)

def abs_diff(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_ge(a, b), U32.sub(a, b), U32.sub(b, a))

# Check diagonal conflict between queen at (r1, c1) and (r2, c2)
def diag_conflict(+c1: U32, +c2: U32, +dist_rows: U32) -> U32:
  Bool.pick(U32, U32.is_eq(abs_diff(c1, c2), dist_rows), 1, 0)

# Total diagonal conflicts in 8-Queens board
def queen_conflicts(p: Perm8) -> U32:
  P8{q0, q1, q2, q3, q4, q5, q6, q7} = p
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

# Fitness: 100 - conflicts (100 = 0 conflicts, perfect solution)
def fitness(p: Perm8) -> U32:
  +c = queen_conflicts(p)
  (100 - c : U32)

type Ind is Data:
  Ind{gene: Perm8, fit: U32}

def Ind.gene(ind: Ind) -> Perm8:
  Ind{g, _} = ind
  g

def Ind.fit(ind: Ind) -> U32:
  Ind{_, f} = ind
  f

type PopTree is Data:
  Leaf{ind: Ind}
  Node{left: PopTree, right: PopTree}

def eval_pop(tree: PopTree) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      +gene = g
      Leaf{Ind{gene, fitness(gene)}}
    case Node{left, right}:
      l r = eval_pop(left) eval_pop(right)
      Node{l, r}

def pick_better(+a: Ind, +b: Ind) -> Ind:
  +fa = Ind.fit(a)
  +fb = Ind.fit(b)
  Bool.pick(Ind, U32.is_ge(fa, fb), a, b)

def best_pop(tree: PopTree) -> Ind:
  match tree:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      bl br = best_pop(left) best_pop(right)
      pick_better(bl, br)

def initial_queens() -> Perm8:
  P8{0, 1, 2, 3, 4, 5, 6, 7}

def shuffle_queens(+p: Perm8, +s: U32) -> Perm8:
  +s1 = step(s)
  +s2 = step(s1)
  +s3 = step(s2)
  +s4 = step(s3)
  +p1 = Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))
  Perm8.swap(p1, U32.mod(s3, 8), U32.mod(s4, 8))

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      +g = shuffle_queens(initial_queens(), seed)
      Leaf{Ind{g, fitness(g)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

def mutate_queens(+p: Perm8, +s: U32) -> Perm8:
  +s1 = step(s)
  +s2 = step(s1)
  Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))

def reproduce(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +s1 = step(seed)
      +s2 = step(s1)
      # 50% bias to elite
      +base = Bool.pick(Perm8, U32.is_zero(U32.and(s1, 1)), ge, g)
      +child = mutate_queens(base, s2)
      Leaf{Ind{child, fitness(child)}}
    case Node{left, right}:
      +seed = seed
      +elite = elite
      l r = reproduce(left, split.fst(seed), elite) reproduce(right, split.snd(seed), elite)
      Node{l, r}

def inject_elite(tree: PopTree, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{_}:
      Leaf{elite}
    case Node{left, right}:
      Node{inject_elite(left, elite), right}

def step_gen(tree: PopTree, +seed: U32) -> PopTree:
  +evaluated = eval_pop(tree)
  +best = best_pop(evaluated)
  +next_pop = reproduce(evaluated, seed, best)
  inject_elite(next_pop, best)

def run_ga(g: Nat, tree: PopTree, +seed: U32) -> PopTree:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = step(seed)
      +next_tree = step_gen(tree, seed)
      run_ga(p, next_tree, next_seed)

def Perm8.show(p: Perm8) -> String:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  "[" ++ U32.show(x0) ++ ", " ++ U32.show(x1) ++ ", " ++ U32.show(x2) ++ ", " ++
  U32.show(x3) ++ ", " ++ U32.show(x4) ++ ", " ++ U32.show(x5) ++ ", " ++
  U32.show(x6) ++ ", " ++ U32.show(x7) ++ "]"

def main_seed() -> U32:
  551122

def main() -> IO(Unit):
  +s0 = main_seed()
  # Depth 6 = 64 individuals in the parallel population tree
  +pop0 = gen_pop(6n, s0)
  +eval0 = eval_pop(pop0)
  +best0 = best_pop(eval0)
  +g0 = Ind.gene(best0)
  +f0 = Ind.fit(best0)
  +c0 = queen_conflicts(g0)

  # Run for 60 generations
  +pop_final = run_ga(60n, eval0, step(s0))
  +eval_final = eval_pop(pop_final)
  +best_fin = best_pop(eval_final)
  +g_fin = Ind.gene(best_fin)
  +f_fin = Ind.fit(best_fin)
  +c_fin = queen_conflicts(g_fin)

  IO.print(
    "=== CENÁRIO 6: PROBLEMA DAS 8-RAINHAS (N-QUEENS) ===\n" ++
    "Tabuleiro: 8x8 (Linhas e colunas exclusivas por permutação, minimiza diagonais)\n" ++
    "População: 64 indivíduos (árvore binária profundidade 6)\n" ++
    "Geração 0  - Conflitos Diagonais: " ++ U32.show(c0) ++ " (Fitness: " ++ U32.show(f0) ++ " / 100) | " ++ Perm8.show(g0) ++ "\n" ++
    "Geração 60 - Conflitos Diagonais: " ++ U32.show(c_fin) ++ " (Fitness: " ++ U32.show(f_fin) ++ " / 100) | " ++ Perm8.show(g_fin) ++ "\n" ++
    "Solução Ótima sem Conflitos? " ++ Bool.show(U32.is_zero(c_fin)) ++ "\n"
  )
