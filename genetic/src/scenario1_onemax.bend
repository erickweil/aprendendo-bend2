import Base

# Xorshift32 PRNG step
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

# Seed-splitting for pure tree parallelism (no unpacking needed)
def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

# Structural popcount over Word(32n)
def popcount.word(n: Nat, w: Word(n)) -> U32:
  match n w:
    case 0n WNil{}:
      0
    case 1n+p WCon{b, tail}:
      match b:
        case True{}:
          U32.inc(popcount.word(p, tail))
        case False{}:
          popcount.word(p, tail)

def popcount(u: U32) -> U32:
  match u:
    case U32{w}:
      popcount.word(32n, w)

# Individual with 32-bit chromosome and cached fitness
type Ind is Data:
  Ind{gene: U32, fit: U32}

def Ind.gene(ind: Ind) -> U32:
  Ind{g, _} = ind
  g

def Ind.fit(ind: Ind) -> U32:
  Ind{_, f} = ind
  f

# Population organized as a balanced binary tree
type PopTree is Data:
  Leaf{ind: Ind}
  Node{left: PopTree, right: PopTree}

# Parallel evaluation of the entire population tree
def eval_pop(tree: PopTree) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      +gene = g
      Leaf{Ind{gene, popcount(gene)}}
    case Node{left, right}:
      l r = eval_pop(left) eval_pop(right)
      Node{l, r}

def pick_better(+a: Ind, +b: Ind) -> Ind:
  +fa = Ind.fit(a)
  +fb = Ind.fit(b)
  Bool.pick(Ind, U32.is_ge(fa, fb), a, b)

# Parallel reduction to find the best individual in the population
def best_pop(tree: PopTree) -> Ind:
  match tree:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      bl br = best_pop(left) best_pop(right)
      pick_better(bl, br)

# Generate a random population tree of depth d
def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      +g = step(seed)
      Leaf{Ind{g, popcount(g)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

# Uniform crossover between two 32-bit chromosomes using a random mask
def crossover(+p1: U32, +p2: U32, +mask: U32) -> U32:
  U32.or(U32.and(mask, p1), U32.and(U32.not(mask), p2))

# Bitwise mutation: flips bits with ~6% probability using bitwise AND of 4 PRNG outputs
def mutate(+gene: U32, +s: U32) -> U32:
  +s1 = step(s)
  +s2 = step(s1)
  +s3 = step(s2)
  +s4 = step(s3)
  +mask = U32.and(U32.and(s1, s2), U32.and(s3, s4))
  U32.xor(gene, mask)

# Parallel reproduction: subtrees cross over and mutate concurrently with elitism
def reproduce(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +s_c = step(seed)
      +s_m = step(s_c)
      # Recombine with elite / mutate
      +child = crossover(g, ge, s_c)
      +mutated = mutate(child, s_m)
      Leaf{Ind{mutated, popcount(mutated)}}
    case Node{left, right}:
      +seed = seed
      +elite = elite
      l r = reproduce(left, split.fst(seed), elite) reproduce(right, split.snd(seed), elite)
      Node{l, r}

# Inject the best individual into the leftmost leaf to guarantee strict elitism
def inject_elite(tree: PopTree, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{_}:
      Leaf{elite}
    case Node{left, right}:
      Node{inject_elite(left, elite), right}

# Single generational step
def step_gen(tree: PopTree, +seed: U32) -> PopTree:
  +evaluated = eval_pop(tree)
  +best = best_pop(evaluated)
  +next_pop = reproduce(evaluated, seed, best)
  inject_elite(next_pop, best)

# Generational loop
def run_ga(g: Nat, tree: PopTree, +seed: U32) -> PopTree:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = step(seed)
      +next_tree = step_gen(tree, seed)
      run_ga(p, next_tree, next_seed)

def initial_seed() -> U32:
  777123

def main() -> IO(Unit):
  +s0 = initial_seed()
  # Depth 5 = 2^5 = 32 indivíduos na árvore paralela
  +pop0 = gen_pop(5n, s0)
  +eval0 = eval_pop(pop0)
  +best0 = best_pop(eval0)
  +f0 = Ind.fit(best0)

  # Executar por 25 gerações
  +pop_final = run_ga(25n, eval0, step(s0))
  +eval_final = eval_pop(pop_final)
  +best_fin = best_pop(eval_final)
  +g_fin = Ind.gene(best_fin)
  +f_fin = Ind.fit(best_fin)

  IO.print(
    "=== CENÁRIO 1: BIT MAXING (ONE-MAX) ===\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Geração 0 - Melhor Fitness: " ++ U32.show(f0) ++ " / 32 bits\n" ++
    "Geração 25 - Melhor Fitness: " ++ U32.show(f_fin) ++ " / 32 bits\n" ++
    "Gene final (U32): " ++ U32.show(g_fin) ++ "\n" ++
    "Solução Ótima Atingida? " ++ Bool.show(U32.is_eq(f_fin, 32)) ++ "\n"
  )
