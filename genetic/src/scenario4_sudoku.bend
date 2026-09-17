import Base

type Board4 is Data:
  B4{
    c00: U32, c01: U32, c02: U32, c03: U32,
    c10: U32, c11: U32, c12: U32, c13: U32,
    c20: U32, c21: U32, c22: U32, c23: U32,
    c30: U32, c31: U32, c32: U32, c33: U32
  }

type Row4 is Data:
  R4{x0: U32, x1: U32, x2: U32, x3: U32}

# Xorshift32 PRNG
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

def eq_cost(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_eq(a, b), 1, 0)

# Conflict count for 4 numbers (all pairs equal)
def group_conflicts(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  (eq_cost(a, b) + eq_cost(a, c) + eq_cost(a, d) +
   eq_cost(b, c) + eq_cost(b, d) + eq_cost(c, d) : U32)

# Total column conflicts + box conflicts
def board_conflicts(b: Board4) -> U32:
  B4{
    c00, c01, c02, c03,
    c10, c11, c12, c13,
    c20, c21, c22, c23,
    c30, c31, c32, c33
  } = b
  +c00 = c00
  +c01 = c01
  +c02 = c02
  +c03 = c03
  +c10 = c10
  +c11 = c11
  +c12 = c12
  +c13 = c13
  +c20 = c20
  +c21 = c21
  +c22 = c22
  +c23 = c23
  +c30 = c30
  +c31 = c31
  +c32 = c32
  +c33 = c33

  # Columns
  +col0 = group_conflicts(c00, c10, c20, c30)
  +col1 = group_conflicts(c01, c11, c21, c31)
  +col2 = group_conflicts(c02, c12, c22, c32)
  +col3 = group_conflicts(c03, c13, c23, c33)

  # 2x2 Subgrids
  +box0 = group_conflicts(c00, c01, c10, c11)
  +box1 = group_conflicts(c02, c03, c12, c13)
  +box2 = group_conflicts(c20, c21, c30, c31)
  +box3 = group_conflicts(c22, c23, c32, c33)

  (col0 + col1 + col2 + col3 + box0 + box1 + box2 + box3 : U32)

# Fitness = 100 - conflicts (100 = 0 conflicts, perfect solution)
def fitness(b: Board4) -> U32:
  +c = board_conflicts(b)
  (100 - c : U32)

type Ind is Data:
  Ind{gene: Board4, fit: U32}

def Ind.gene(ind: Ind) -> Board4:
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

# Initial board with fixed clues:
# Row 0: [1, 2, 3, 4] (1 and 4 fixed clues)
# Row 1: [1, 2, 3, 4]
# Row 2: [1, 2, 3, 4]
# Row 3: [4, 2, 3, 1] (4 and 1 fixed clues)
def base_board() -> Board4:
  B4{
    1, 2, 3, 4,
    1, 2, 3, 4,
    1, 2, 3, 4,
    4, 2, 3, 1
  }

# Swap within Row 0 (only between non-clues c01 and c02)
def swap_r0(b: Board4) -> Board4:
  B4{c00, c01, c02, c03, c10, c11, c12, c13, c20, c21, c22, c23, c30, c31, c32, c33} = b
  B4{c00, c02, c01, c03, c10, c11, c12, c13, c20, c21, c22, c23, c30, c31, c32, c33}

# Swap within Row 3 (only between non-clues c31 and c32)
def swap_r3(b: Board4) -> Board4:
  B4{c00, c01, c02, c03, c10, c11, c12, c13, c20, c21, c22, c23, c30, c31, c32, c33} = b
  B4{c00, c01, c02, c03, c10, c11, c12, c13, c20, c21, c22, c23, c30, c32, c31, c33}

# All 6 swap combinations of 4 elements:
def swap_row4(+a: U32, +b: U32, +c: U32, +d: U32, +k: U32) -> Row4:
  Bool.pick(Row4, U32.is_eq(k, 0), R4{b, a, c, d},
    Bool.pick(Row4, U32.is_eq(k, 1), R4{c, b, a, d},
      Bool.pick(Row4, U32.is_eq(k, 2), R4{d, b, c, a},
        Bool.pick(Row4, U32.is_eq(k, 3), R4{a, c, b, d},
          Bool.pick(Row4, U32.is_eq(k, 4), R4{a, d, c, b},
            R4{a, b, d, c})))))

def swap_r1.apply(b: Board4, r: Row4) -> Board4:
  B4{c00, c01, c02, c03, _, _, _, _, c20, c21, c22, c23, c30, c31, c32, c33} = b
  R4{n10, n11, n12, n13} = r
  B4{c00, c01, c02, c03, n10, n11, n12, n13, c20, c21, c22, c23, c30, c31, c32, c33}

def swap_r1(+b: Board4, +k: U32) -> Board4:
  B4{_, _, _, _, c10, c11, c12, c13, _, _, _, _, _, _, _, _} = b
  swap_r1.apply(b, swap_row4(c10, c11, c12, c13, k))

def swap_r2.apply(b: Board4, r: Row4) -> Board4:
  B4{c00, c01, c02, c03, c10, c11, c12, c13, _, _, _, _, c30, c31, c32, c33} = b
  R4{n20, n21, n22, n23} = r
  B4{c00, c01, c02, c03, c10, c11, c12, c13, n20, n21, n22, n23, c30, c31, c32, c33}

def swap_r2(+b: Board4, +k: U32) -> Board4:
  B4{_, _, _, _, _, _, _, _, c20, c21, c22, c23, _, _, _, _} = b
  swap_r2.apply(b, swap_row4(c20, c21, c22, c23, k))

# Mutate a row chosen by PRNG (preserves row multiset!)
def mutate_board(+b: Board4, +s: U32) -> Board4:
  +s1 = step(s)
  +s2 = step(s1)
  +row = U32.mod(s1, 4)
  +k = U32.mod(s2, 6)
  Bool.pick(Board4, U32.is_eq(row, 0), swap_r0(b),
    Bool.pick(Board4, U32.is_eq(row, 1), swap_r1(b, k),
      Bool.pick(Board4, U32.is_eq(row, 2), swap_r2(b, k), swap_r3(b))))

def shuffle_board(+b: Board4, +s: U32) -> Board4:
  +s1 = step(s)
  +s2 = step(s1)
  +b1 = mutate_board(b, s1)
  mutate_board(b1, s2)

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      +g = shuffle_board(base_board(), seed)
      Leaf{Ind{g, fitness(g)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

def reproduce(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +s1 = step(seed)
      +s2 = step(s1)
      # 50% bias towards elite board
      +base = Bool.pick(Board4, U32.is_zero(U32.and(s1, 1)), ge, g)
      +child = mutate_board(base, s2)
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

def Board4.show(b: Board4) -> String:
  B4{
    c00, c01, c02, c03,
    c10, c11, c12, c13,
    c20, c21, c22, c23,
    c30, c31, c32, c33
  } = b
  "\n[" ++ U32.show(c00) ++ " " ++ U32.show(c01) ++ " | " ++ U32.show(c02) ++ " " ++ U32.show(c03) ++ "]\n" ++
  "[" ++ U32.show(c10) ++ " " ++ U32.show(c11) ++ " | " ++ U32.show(c12) ++ " " ++ U32.show(c13) ++ "]\n" ++
  "------+------\n" ++
  "[" ++ U32.show(c20) ++ " " ++ U32.show(c21) ++ " | " ++ U32.show(c22) ++ " " ++ U32.show(c23) ++ "]\n" ++
  "[" ++ U32.show(c30) ++ " " ++ U32.show(c31) ++ " | " ++ U32.show(c32) ++ " " ++ U32.show(c33) ++ "]\n"

def main_seed() -> U32:
  334455

def main() -> IO(Unit):
  +s0 = main_seed()
  # Depth 5 = 32 individuals in the parallel population tree
  +pop0 = gen_pop(5n, s0)
  +eval0 = eval_pop(pop0)
  +best0 = best_pop(eval0)
  +g0 = Ind.gene(best0)
  +f0 = Ind.fit(best0)
  +c0 = board_conflicts(g0)

  # Run for 35 generations
  +pop_final = run_ga(35n, eval0, step(s0))
  +eval_final = eval_pop(pop_final)
  +best_fin = best_pop(eval_final)
  +g_fin = Ind.gene(best_fin)
  +f_fin = Ind.fit(best_fin)
  +c_fin = board_conflicts(g_fin)

  IO.print(
    "=== CENÁRIO 4: SUDOKU SOLVER ===\n" ++
    "Grade: 4x4 (Linhas preservadas por construção, conflitos em colunas e subgrades 2x2)\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Geração 0  - Conflitos: " ++ U32.show(c0) ++ " (Fitness: " ++ U32.show(f0) ++ " / 100)" ++ Board4.show(g0) ++ "\n" ++
    "Geração 35 - Conflitos: " ++ U32.show(c_fin) ++ " (Fitness: " ++ U32.show(f_fin) ++ " / 100)" ++ Board4.show(g_fin) ++ "\n" ++
    "Sudoku Resolvido com Sucesso (0 conflitos)? " ++ Bool.show(U32.is_zero(c_fin)) ++ "\n"
  )
