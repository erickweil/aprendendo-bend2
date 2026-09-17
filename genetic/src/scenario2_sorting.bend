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

def pair_score(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_le(a, b), 1, 0)

# Fitness = count of ordered pairs (xi <= xj for i < j). Max = 28.
def fitness(p: Perm8) -> U32:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  +x0 = x0
  +x1 = x1
  +x2 = x2
  +x3 = x3
  +x4 = x4
  +x5 = x5
  +x6 = x6
  +x7 = x7

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

def Perm8.show(p: Perm8) -> String:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  "[" ++ U32.show(x0) ++ ", " ++ U32.show(x1) ++ ", " ++ U32.show(x2) ++ ", " ++
  U32.show(x3) ++ ", " ++ U32.show(x4) ++ ", " ++ U32.show(x5) ++ ", " ++
  U32.show(x6) ++ ", " ++ U32.show(x7) ++ "]"

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

# Shuffle helper to create a random permutation from initial state
def shuffle_perm(+p: Perm8, +s: U32) -> Perm8:
  +s1 = step(s)
  +s2 = step(s1)
  +s3 = step(s2)
  +s4 = step(s3)
  +p1 = Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))
  Perm8.swap(p1, U32.mod(s3, 8), U32.mod(s4, 8))

def initial_perm() -> Perm8:
  P8{7, 3, 5, 1, 6, 2, 4, 0}

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      +g = shuffle_perm(initial_perm(), seed)
      Leaf{Ind{g, fitness(g)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

# Mutation: swaps two random positions in the permutation
def mutate_perm(+p: Perm8, +s: U32) -> Perm8:
  +s1 = step(s)
  +s2 = step(s1)
  Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))

# Reproduce: mutate from current or elite
def reproduce(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +s1 = step(seed)
      +s2 = step(s1)
      # 50% chance to evolve elite, 50% to evolve current individual
      +base = Bool.pick(Perm8, U32.is_zero(U32.and(s1, 1)), ge, g)
      +child = mutate_perm(base, s2)
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
  889911

def main() -> IO(Unit):
  +s0 = main_seed()
  # Depth 5 = 32 individuals
  +pop0 = gen_pop(5n, s0)
  +eval0 = eval_pop(pop0)
  +best0 = best_pop(eval0)
  +g0 = Ind.gene(best0)
  +f0 = Ind.fit(best0)

  # Run for 40 generations
  +pop_final = run_ga(40n, eval0, step(s0))
  +eval_final = eval_pop(pop_final)
  +best_fin = best_pop(eval_final)
  +g_fin = Ind.gene(best_fin)
  +f_fin = Ind.fit(best_fin)

  IO.print(
    "=== CENÁRIO 2: ORDENAR NÚMEROS (NUMBER SORTING) ===\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Geração 0  - Melhor Fitness: " ++ U32.show(f0) ++ " / 28 | " ++ Perm8.show(g0) ++ "\n" ++
    "Geração 40 - Melhor Fitness: " ++ U32.show(f_fin) ++ " / 28 | " ++ Perm8.show(g_fin) ++ "\n" ++
    "Vetor Ordenado com Sucesso? " ++ Bool.show(U32.is_eq(f_fin, 28)) ++ "\n"
  )
