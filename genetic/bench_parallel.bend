import Base
import ./utils/random.bend as R
import ./utils/poptree.bend as T

# ================================================================
# BENCHMARK DE PARALELISMO COARSE-GRAINED (1 THREAD VS 4 THREADS)
# ================================================================
# Demonstra escala linear com modelo de ilhas e tarefas macro-paralelas
# ================================================================

type Perm8 is Data:
  P8{x0: U32, x1: U32, x2: U32, x3: U32, x4: U32, x5: U32, x6: U32, x7: U32}

def make_perm8(+x0: U32, +x1: U32, +x2: U32, +x3: U32,
               +x4: U32, +x5: U32, +x6: U32, +x7: U32) -> Perm8:
  P8{x0, x1, x2, x3, x4, x5, x6, x7}

def Perm8.get(+p: Perm8, +idx: U32) -> U32:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  match idx:
    case 0: x0
    case 1: x1
    case 2: x2
    case 3: x3
    case 4: x4
    case 5: x5
    case 6: x6
    case _: x7

def Perm8.set(+p: Perm8, +idx: U32, +val: U32) -> Perm8:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  make_perm8(
    Bool.pick(U32, U32.is_eq(idx, 0), val, x0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, x1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, x2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, x3),
    Bool.pick(U32, U32.is_eq(idx, 4), val, x4),
    Bool.pick(U32, U32.is_eq(idx, 5), val, x5),
    Bool.pick(U32, U32.is_eq(idx, 6), val, x6),
    Bool.pick(U32, U32.is_eq(idx, 7), val, x7)
  )

def Perm8.swap(+p: Perm8, +i: U32, +j: U32) -> Perm8:
  +vi = Perm8.get(p, i)
  +vj = Perm8.get(p, j)
  Perm8.set(Perm8.set(p, i, vj), j, vi)

def city_dist(+c1: U32, +c2: U32) -> U32:
  +d = Bool.pick(U32, U32.is_ge(c1, c2), (c1 - c2 : U32), (c2 - c1 : U32))
  (d * 10 : U32)

def tour_distance(+p: Perm8) -> U32:
  P8{c0, c1, c2, c3, c4, c5, c6, c7} = p
  (city_dist(c0, c1) + city_dist(c1, c2) + city_dist(c2, c3) + city_dist(c3, c4) +
   city_dist(c4, c5) + city_dist(c5, c6) + city_dist(c6, c7) + city_dist(c7, c0) : U32)

def fitness(+p: Perm8) -> U32:
  +d = tour_distance(p)
  Bool.pick(U32, U32.is_gt(d, 1000), 0, (1000 - d : U32))

type Ind is Data:
  Ind{gene: Perm8, fit: U32}

def make_ind(+g: Perm8) -> Ind:
  Ind{g, fitness(g)}

def Ind.gene(i: Ind) -> Perm8:
  Ind{g, _} = i
  g

def Ind.fit(i: Ind) -> U32:
  Ind{_, f} = i
  f

def pick_better(+a: Ind, +b: Ind) -> Ind:
  Bool.pick(Ind, U32.is_ge(Ind.fit(a), Ind.fit(b)), a, b)

type PopTree is Data:
  Leaf{ind: Ind}
  Node{left: PopTree, right: PopTree}

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      Leaf{make_ind(make_perm8(0, 1, 2, 3, 4, 5, 6, 7))}
    case 1n+p:
      +p = p; +seed = seed
      l r = gen_pop(p, R.split.fst(seed)) gen_pop(p, R.split.snd(seed))
      Node{l, r}

def mutate_tour(+p: Perm8, +s: U32) -> Perm8:
  +s1 = R.step(s)
  +s2 = R.step(s1)
  Perm8.swap(p, U32.mod(s1, 8), U32.mod(s2, 8))

def best_pop_seq(tree: PopTree) -> Ind:
  match tree:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      +bl = best_pop_seq(left)
      +br = best_pop_seq(right)
      pick_better(bl, br)

def reproduce_seq(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +s1 = R.step(seed)
      +s2 = R.step(s1)
      +base = Bool.pick(Perm8, U32.is_lt(U32.mod(s1, 10), 6), ge, g)
      +child = mutate_tour(base, s2)
      Leaf{make_ind(child)}
    case Node{left, right}:
      +seed = seed; +elite = elite
      +l = reproduce_seq(left, R.split.fst(seed), elite)
      +r = reproduce_seq(right, R.split.snd(seed), elite)
      Node{l, r}

def step_gen_seq(+tree: PopTree, +seed: U32) -> PopTree:
  +best = best_pop_seq(tree)
  reproduce_seq(tree, seed, best)

def run_island_seq(g: Nat, tree: PopTree, +seed: U32) -> PopTree:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = R.step(seed)
      +next_tree = step_gen_seq(tree, seed)
      run_island_seq(p, next_tree, next_seed)

type ArchTree is Data:
  SingleIsland{tree: PopTree}
  ArchBranch{left: ArchTree, right: ArchTree}

def gen_arch(d: Nat, +seed: U32, pop_d: Nat) -> ArchTree:
  match d:
    case 0n:
      SingleIsland{gen_pop(pop_d, seed)}
    case 1n+p:
      +p = p; +seed = seed; +pop_d = pop_d
      l r = gen_arch(p, R.split.fst(seed), pop_d) gen_arch(p, R.split.snd(seed), pop_d)
      ArchBranch{l, r}

def evolve_arch(arch: ArchTree, +seed: U32, e: Nat) -> ArchTree:
  match arch:
    case SingleIsland{tree}:
      SingleIsland{run_island_seq(e, tree, seed)}
    case ArchBranch{left, right}:
      +seed = seed; +e = e
      l r = evolve_arch(left, R.split.fst(seed), e) evolve_arch(right, R.split.snd(seed), e)
      ArchBranch{l, r}

def best_arch(arch: ArchTree) -> Ind:
  match arch:
    case SingleIsland{tree}:
      best_pop_seq(tree)
    case ArchBranch{left, right}:
      bl br = best_arch(left) best_arch(right)
      pick_better(bl, br)

def migrate_champ(arch: ArchTree, +champ: Ind) -> ArchTree:
  match arch:
    case SingleIsland{tree}:
      match tree:
        case Leaf{_}:
          SingleIsland{Leaf{champ}}
        case Node{left, right}:
          SingleIsland{Node{Leaf{champ}, right}}
    case ArchBranch{left, right}:
      +champ = champ
      ArchBranch{migrate_champ(left, champ), migrate_champ(right, champ)}

def run_arch_epochs(epochs: Nat, arch: ArchTree, +seed: U32, e: Nat) -> ArchTree:
  match epochs:
    case 0n:
      arch
    case 1n+p:
      +next_seed = R.step(seed); +e = e
      +evolved = evolve_arch(arch, seed, e)
      +champ = best_arch(evolved)
      +migrated = migrate_champ(evolved, champ)
      run_arch_epochs(p, migrated, next_seed, e)

def main() -> IO(Unit):
  +s0 = {12345678 : U32}
  # 4 Ilhas x 64 indivíduos = 256 indivíduos
  +arch0 = gen_arch(2n, s0, 6n)
  # 100 épocas x 50 gerações = 5.000 gerações totais por ilha (1.280.000 avaliações)
  +arch_fin = run_arch_epochs(100n, arch0, R.step(s0), 50n)
  +champ_fin = best_arch(arch_fin)
  +d_fin = tour_distance(Ind.gene(champ_fin))
  IO.print("PGA Benchmark - Distancia Campeao: " ++ U32.show(d_fin) ++ "\n")
