import Base

# ================================================================
# BEND 2: PARALLEL ISLAND MODEL (MODELO DE ILHAS / ARQUIPÉLAGO)
# Múltiplas ilhas evoluem independentemente em núcleos paralelos.
# A cada época (epoch), o campeão global migra para todas as ilhas.
# ================================================================

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

# 8 City Coordinates (X, Y)
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

def dist(+c1: U32, +c2: U32) -> U32:
  +dx = abs_diff(city_x(c1), city_x(c2))
  +dy = abs_diff(city_y(c1), city_y(c2))
  (dx + dy : U32)

def tour_distance(p: Perm8) -> U32:
  P8{c0, c1, c2, c3, c4, c5, c6, c7} = p
  +c0 = c0; +c1 = c1; +c2 = c2; +c3 = c3
  +c4 = c4; +c5 = c5; +c6 = c6; +c7 = c7

  +d0 = dist(c0, c1); +d1 = dist(c1, c2); +d2 = dist(c2, c3); +d3 = dist(c3, c4)
  +d4 = dist(c4, c5); +d5 = dist(c5, c6); +d6 = dist(c6, c7); +d7 = dist(c7, c0)
  (d0 + d1 + d2 + d3 + d4 + d5 + d6 + d7 : U32)

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

def shuffle_tour(+p: Perm8, +s: U32) -> Perm8:
  +s1 = step(s); +s2 = step(s1); +s3 = step(s2); +s4 = step(s3)
  +p1 = Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))
  Perm8.swap(p1, U32.mod(s3, 8), U32.mod(s4, 8))

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      +g = shuffle_tour(P8{0, 4, 1, 5, 2, 6, 3, 7}, seed)
      Leaf{Ind{g, fitness(g)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

def mutate_tour(+p: Perm8, +s: U32) -> Perm8:
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

def run_island_epoch(g: Nat, tree: PopTree, +seed: U32) -> PopTree:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = step(seed)
      +next_tree = step_gen(tree, seed)
      run_island_epoch(p, next_tree, next_seed)

# ================================================================
# ESTRUTURA DO ARQUIPÉLAGO (ISLAND MODEL)
# ================================================================

type Archipelago is Data:
  SingleIsland{tree: PopTree}
  ArchBranch{left: Archipelago, right: Archipelago}

# Generate 2^d islands in parallel
def gen_archipelago(d: Nat, +seed: U32) -> Archipelago:
  match d:
    case 0n:
      # Each island has depth 4 = 16 individuals
      SingleIsland{gen_pop(4n, seed)}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_archipelago(p, split.fst(seed)) gen_archipelago(p, split.snd(seed))
      ArchBranch{l, r}

# Parallel evaluation of the entire archipelago
def eval_archipelago(arch: Archipelago) -> Archipelago:
  match arch:
    case SingleIsland{tree}:
      SingleIsland{eval_pop(tree)}
    case ArchBranch{left, right}:
      l r = eval_archipelago(left) eval_archipelago(right)
      ArchBranch{l, r}

# Parallel tree reduction to find the global champion across ALL islands
def best_archipelago(arch: Archipelago) -> Ind:
  match arch:
    case SingleIsland{tree}:
      best_pop(tree)
    case ArchBranch{left, right}:
      bl br = best_archipelago(left) best_archipelago(right)
      pick_better(bl, br)

# Evolve all islands concurrently for an epoch of E generations
def evolve_archipelago(arch: Archipelago, +seed: U32, e: Nat) -> Archipelago:
  match arch:
    case SingleIsland{tree}:
      SingleIsland{run_island_epoch(e, tree, seed)}
    case ArchBranch{left, right}:
      +seed = seed
      +e = e
      l r = evolve_archipelago(left, split.fst(seed), e) evolve_archipelago(right, split.snd(seed), e)
      ArchBranch{l, r}

# Broadcast / Migrate the global champion into each island
def migrate_champion(arch: Archipelago, +champion: Ind) -> Archipelago:
  match arch:
    case SingleIsland{tree}:
      SingleIsland{inject_elite(tree, champion)}
    case ArchBranch{left, right}:
      +champion = champion
      ArchBranch{migrate_champion(left, champion), migrate_champion(right, champion)}

# Multi-epoch loop with migration
def run_archipelago(epochs: Nat, arch: Archipelago, +seed: U32, epoch_len: Nat) -> Archipelago:
  match epochs:
    case 0n:
      arch
    case 1n+p:
      +next_seed = step(seed)
      +epoch_len = epoch_len
      # 1. All islands evolve concurrently
      +evolved = evolve_archipelago(arch, seed, epoch_len)
      # 2. Extract global champion across all islands
      +evaluated = eval_archipelago(evolved)
      +champion = best_archipelago(evaluated)
      # 3. Migrate champion to all islands
      +migrated = migrate_champion(evaluated, champion)
      run_archipelago(p, migrated, next_seed, epoch_len)

def Perm8.show(p: Perm8) -> String:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  "[" ++ U32.show(x0) ++ ", " ++ U32.show(x1) ++ ", " ++ U32.show(x2) ++ ", " ++
  U32.show(x3) ++ ", " ++ U32.show(x4) ++ ", " ++ U32.show(x5) ++ ", " ++
  U32.show(x6) ++ ", " ++ U32.show(x7) ++ "]"

def main_seed() -> U32:
  654321

def main() -> IO(Unit):
  +s0 = main_seed()
  # 2^2 = 4 islands, each with 16 individuals = 64 total individuals in the archipelago
  +arch0 = gen_archipelago(2n, s0)
  +eval0 = eval_archipelago(arch0)
  +champ0 = best_archipelago(eval0)
  +g0 = Ind.gene(champ0)
  +d0 = tour_distance(g0)

  # Run 5 epochs of 10 generations each = 50 total generations with periodic migration!
  +arch_final = run_archipelago(5n, eval0, step(s0), 10n)
  +eval_final = eval_archipelago(arch_final)
  +champ_fin = best_archipelago(eval_final)
  +g_fin = Ind.gene(champ_fin)
  +d_fin = tour_distance(g_fin)

  IO.print(
    "=== MODELO DE ILHAS PARALELAS (PARALLEL ISLAND MODEL - PGA) ===\n" ++
    "Arquipélago: 4 Ilhas Independentes x 16 indivíduos = 64 indivíduos\n" ++
    "Paralelismo: Cada ilha evolui isoladamente em um fluxo próprio\n" ++
    "Migração: Campeão global migrado para todas as ilhas a cada 10 gerações\n" ++
    "Início    - Campeão Distância: " ++ U32.show(d0) ++ " | " ++ Perm8.show(g0) ++ "\n" ++
    "Final     - Campeão Distância: " ++ U32.show(d_fin) ++ " | " ++ Perm8.show(g_fin) ++ "\n" ++
    "Solução Ótima Alcançada no Arquipélago? " ++ Bool.show(U32.is_eq(d_fin, 240)) ++ "\n"
  )
