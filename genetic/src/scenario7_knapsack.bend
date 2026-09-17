import Base

# Xorshift32 PRNG
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

def item_weight(+idx: U32) -> U32:
  Bool.pick(U32, U32.is_lt(idx, 5),
    Bool.pick(U32, U32.is_lt(idx, 3),
      Bool.pick(U32, U32.is_eq(idx, 0), 10, Bool.pick(U32, U32.is_eq(idx, 1), 15, 20)),
      Bool.pick(U32, U32.is_eq(idx, 3), 25, 30)),
    Bool.pick(U32, U32.is_lt(idx, 8),
      Bool.pick(U32, U32.is_eq(idx, 5), 12, Bool.pick(U32, U32.is_eq(idx, 6), 18, 8)),
      Bool.pick(U32, U32.is_eq(idx, 8), 22, 14)))

def item_value(+idx: U32) -> U32:
  Bool.pick(U32, U32.is_lt(idx, 5),
    Bool.pick(U32, U32.is_lt(idx, 3),
      Bool.pick(U32, U32.is_eq(idx, 0), 20, Bool.pick(U32, U32.is_eq(idx, 1), 30, 40)),
      Bool.pick(U32, U32.is_eq(idx, 3), 55, 60)),
    Bool.pick(U32, U32.is_lt(idx, 8),
      Bool.pick(U32, U32.is_eq(idx, 5), 25, Bool.pick(U32, U32.is_eq(idx, 6), 38, 18)),
      Bool.pick(U32, U32.is_eq(idx, 8), 50, 32)))

# Bit tester for item inclusion
def bit_selected(+mask: U32, +bit: Nat) -> Bool:
  U32.is_ne(U32.and(mask, U32.shln(1, bit)), 0)

# Calculate total weight of 10 items
def total_weight(+mask: U32) -> U32:
  +w0 = Bool.pick(U32, bit_selected(mask, 0n), item_weight(0), 0)
  +w1 = Bool.pick(U32, bit_selected(mask, 1n), item_weight(1), 0)
  +w2 = Bool.pick(U32, bit_selected(mask, 2n), item_weight(2), 0)
  +w3 = Bool.pick(U32, bit_selected(mask, 3n), item_weight(3), 0)
  +w4 = Bool.pick(U32, bit_selected(mask, 4n), item_weight(4), 0)
  +w5 = Bool.pick(U32, bit_selected(mask, 5n), item_weight(5), 0)
  +w6 = Bool.pick(U32, bit_selected(mask, 6n), item_weight(6), 0)
  +w7 = Bool.pick(U32, bit_selected(mask, 7n), item_weight(7), 0)
  +w8 = Bool.pick(U32, bit_selected(mask, 8n), item_weight(8), 0)
  +w9 = Bool.pick(U32, bit_selected(mask, 9n), item_weight(9), 0)
  (w0 + w1 + w2 + w3 + w4 + w5 + w6 + w7 + w8 + w9 : U32)

# Calculate total value of 10 items
def total_value(+mask: U32) -> U32:
  +v0 = Bool.pick(U32, bit_selected(mask, 0n), item_value(0), 0)
  +v1 = Bool.pick(U32, bit_selected(mask, 1n), item_value(1), 0)
  +v2 = Bool.pick(U32, bit_selected(mask, 2n), item_value(2), 0)
  +v3 = Bool.pick(U32, bit_selected(mask, 3n), item_value(3), 0)
  +v4 = Bool.pick(U32, bit_selected(mask, 4n), item_value(4), 0)
  +v5 = Bool.pick(U32, bit_selected(mask, 5n), item_value(5), 0)
  +v6 = Bool.pick(U32, bit_selected(mask, 6n), item_value(6), 0)
  +v7 = Bool.pick(U32, bit_selected(mask, 7n), item_value(7), 0)
  +v8 = Bool.pick(U32, bit_selected(mask, 8n), item_value(8), 0)
  +v9 = Bool.pick(U32, bit_selected(mask, 9n), item_value(9), 0)
  (v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8 + v9 : U32)

# Max capacity: 80
def max_capacity() -> U32:
  80

# Fitness function:
# If weight <= 80: value
# If weight > 80: penalized value
def fitness(+mask: U32) -> U32:
  +w = total_weight(mask)
  +v = total_value(mask)
  +cap = max_capacity()
  Bool.pick(U32, U32.is_le(w, cap),
    v,
    Bool.pick(U32, U32.is_gt((v - U32.mul(U32.sub(w, cap), 4) : U32), 0),
      (v - U32.mul(U32.sub(w, cap), 4) : U32),
      0))

type Ind is Data:
  Ind{gene: U32, fit: U32}

def Ind.gene(ind: Ind) -> U32:
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

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      # Keep 10 bits
      +g = U32.and(step(seed), 1023)
      Leaf{Ind{g, fitness(g)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

def crossover(+p1: U32, +p2: U32, +mask: U32) -> U32:
  U32.and(U32.or(U32.and(mask, p1), U32.and(U32.not(mask), p2)), 1023)

def mutate_mask(+gene: U32, +s: U32) -> U32:
  +s1 = step(s)
  +bit = U32.mod(s1, 10)
  +flip = U32.shln(1, U32.to_nat(bit))
  U32.xor(gene, flip)

def reproduce(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +s1 = step(seed)
      +s2 = step(s1)
      +s3 = step(s2)
      +crossed = crossover(g, ge, s1)
      +child = mutate_mask(crossed, s2)
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
  223344

def main() -> IO(Unit):
  +s0 = main_seed()
  # Depth 5 = 32 individuals
  +pop0 = gen_pop(5n, s0)
  +eval0 = eval_pop(pop0)
  +best0 = best_pop(eval0)
  +g0 = Ind.gene(best0)
  +w0 = total_weight(g0)
  +v0 = total_value(g0)

  # Run for 35 generations
  +pop_final = run_ga(35n, eval0, step(s0))
  +eval_final = eval_pop(pop_final)
  +best_fin = best_pop(eval_final)
  +g_fin = Ind.gene(best_fin)
  +w_fin = total_weight(g_fin)
  +v_fin = total_value(g_fin)

  IO.print(
    "=== CENÁRIO 7: PROBLEMA DA MOCHILA (0/1 KNAPSACK) ===\n" ++
    "Itens: 10 itens com pesos e valores | Capacidade Máxima: " ++ U32.show(max_capacity()) ++ " kg\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Geração 0  - Valor: " ++ U32.show(v0) ++ " | Peso: " ++ U32.show(w0) ++ " kg (Máscara: " ++ U32.show(g0) ++ ")\n" ++
    "Geração 35 - Valor: " ++ U32.show(v_fin) ++ " | Peso: " ++ U32.show(w_fin) ++ " kg (Máscara: " ++ U32.show(g_fin) ++ ")\n" ++
    "Solução Ótima (Valor >= 175 e Peso <= 80)? " ++ Bool.show(Bool.and(U32.is_ge(v_fin, 175), U32.is_le(w_fin, 80))) ++ "\n"
  )
