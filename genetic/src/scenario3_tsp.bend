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

def Perm8.show(p: Perm8) -> String:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  "[" ++ U32.show(x0) ++ ", " ++ U32.show(x1) ++ ", " ++ U32.show(x2) ++ ", " ++
  U32.show(x3) ++ ", " ++ U32.show(x4) ++ ", " ++ U32.show(x5) ++ ", " ++
  U32.show(x6) ++ ", " ++ U32.show(x7) ++ "]"

# 8 City Coordinates (X, Y)
# C0=(20, 20), C1=(20, 50), C2=(20, 80), C3=(50, 80)
# C4=(80, 80), C5=(80, 50), C6=(80, 20), C7=(50, 20)
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

# Manhattan distance between two cities
def dist(+c1: U32, +c2: U32) -> U32:
  +dx = abs_diff(city_x(c1), city_x(c2))
  +dy = abs_diff(city_y(c1), city_y(c2))
  (dx + dy : U32)

# Total tour distance (closed cycle)
def tour_distance(p: Perm8) -> U32:
  P8{c0, c1, c2, c3, c4, c5, c6, c7} = p
  +c0 = c0
  +c1 = c1
  +c2 = c2
  +c3 = c3
  +c4 = c4
  +c5 = c5
  +c6 = c6
  +c7 = c7

  +d0 = dist(c0, c1)
  +d1 = dist(c1, c2)
  +d2 = dist(c2, c3)
  +d3 = dist(c3, c4)
  +d4 = dist(c4, c5)
  +d5 = dist(c5, c6)
  +d6 = dist(c6, c7)
  +d7 = dist(c7, c0)

  (d0 + d1 + d2 + d3 + d4 + d5 + d6 + d7 : U32)

# Fitness = 1000 - tour_distance (higher is better; 1000 - 240 = 760 is optimal)
def fitness(p: Perm8) -> U32:
  +d = tour_distance(p)
  (1000 - d : U32)

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

# Initial scrambled permutation
def initial_tour() -> Perm8:
  P8{0, 4, 1, 5, 2, 6, 3, 7}

def shuffle_tour(+p: Perm8, +s: U32) -> Perm8:
  +s1 = step(s)
  +s2 = step(s1)
  +s3 = step(s2)
  +s4 = step(s3)
  +p1 = Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))
  Perm8.swap(p1, U32.mod(s3, 8), U32.mod(s4, 8))

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      +g = shuffle_tour(initial_tour(), seed)
      Leaf{Ind{g, fitness(g)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

# Mutation: 2-opt swap of two cities
def mutate_tour(+p: Perm8, +s: U32) -> Perm8:
  +s1 = step(s)
  +s2 = step(s1)
  Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))

# Parallel reproduction: evolve towards optimal tour with elitism
def reproduce(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +s1 = step(seed)
      +s2 = step(s1)
      # 60% bias towards elite tour
      +base = Bool.pick(Perm8, U32.is_lt(U32.mod(s1, 10), 6), ge, g)
      +child = mutate_tour(base, s2)
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

def main_seed() -> U32:
  456789

def main() -> IO(Unit):
  +s0 = main_seed()
  # Depth 5 = 32 individuals in the parallel population tree
  +pop0 = gen_pop(5n, s0)
  +eval0 = eval_pop(pop0)
  +best0 = best_pop(eval0)
  +g0 = Ind.gene(best0)
  +f0 = Ind.fit(best0)
  +d0 = tour_distance(g0)

  # Run for 50 generations
  +pop_final = run_ga(50n, eval0, step(s0))
  +eval_final = eval_pop(pop_final)
  +best_fin = best_pop(eval_final)
  +g_fin = Ind.gene(best_fin)
  +f_fin = Ind.fit(best_fin)
  +d_fin = tour_distance(g_fin)

  IO.print(
    "=== CENÁRIO 3: CAIXEIRO VIAJANTE (TSP) ===\n" ++
    "Cidades: 8 no plano 2D (distância mínima ótima teórica = 240)\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Geração 0  - Distância: " ++ U32.show(d0) ++ " (Fitness: " ++ U32.show(f0) ++ ") | Rota: " ++ Perm8.show(g0) ++ "\n" ++
    "Geração 50 - Distância: " ++ U32.show(d_fin) ++ " (Fitness: " ++ U32.show(f_fin) ++ ") | Rota: " ++ Perm8.show(g_fin) ++ "\n" ++
    "Rota Ótima Alcançada? " ++ Bool.show(U32.is_eq(d_fin, 240)) ++ "\n"
  )
