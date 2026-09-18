import Base

# PRNG Xorshift32
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

def split.trd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 1013904223))

def split.fth(+seed: U32) -> U32:
  step(U32.xor(step(seed), 3141592653))

# Deceptive 4-Bit Trap Function
# 4 ones -> 4 (Global Optimum)
# 0 ones -> 3 (Local Optimum Trap)
# 1 one  -> 2
# 2 ones -> 1
# 3 ones -> 0 (Fitness valley)
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

def trap4(+bits: U32) -> U32:
  +c = popcount(U32.and(bits, 15))
  Bool.pick(U32, U32.is_eq(c, 4), 4,
    Bool.pick(U32, U32.is_eq(c, 0), 3,
      Bool.pick(U32, U32.is_eq(c, 1), 2,
        Bool.pick(U32, U32.is_eq(c, 2), 1, 0))))

# 8 concatenated 4-bit traps = 32 bits
# Max possible fitness = 8 * 4 = 32
# Deceptive local optimum = 8 * 3 = 24
def eval_deceptive_trap(+gene: U32) -> U32:
  +t0 = trap4(gene)
  +t1 = trap4(U32.shrn(gene, 4n))
  +t2 = trap4(U32.shrn(gene, 8n))
  +t3 = trap4(U32.shrn(gene, 12n))
  +t4 = trap4(U32.shrn(gene, 16n))
  +t5 = trap4(U32.shrn(gene, 20n))
  +t6 = trap4(U32.shrn(gene, 24n))
  +t7 = trap4(U32.shrn(gene, 28n))
  (t0 + t1 + t2 + t3 + t4 + t5 + t6 + t7 : U32)

type Ind is Data:
  Ind{gene: U32, fit: U32}

def Ind.gene(i: Ind) -> U32:
  Ind{g, _} = i
  g

def Ind.fit(i: Ind) -> U32:
  Ind{_, f} = i
  f

def make_ind(+gene: U32) -> Ind:
  Ind{gene, eval_deceptive_trap(gene)}

# QuadTree Population Structure (2D spatial layout)
type QuadTree is Data:
  QLeaf{cell: Ind}
  QNode{tl: QuadTree, tr: QuadTree, bl: QuadTree, br: QuadTree}

def pick_better(+a: Ind, +b: Ind) -> Ind:
  Bool.pick(Ind, U32.is_ge(Ind.fit(a), Ind.fit(b)), a, b)

def quad_best(q: QuadTree) -> Ind:
  match q:
    case QLeaf{cell}:
      cell
    case QNode{tl, tr, bl, br}:
      b1 b2 = quad_best(tl) quad_best(tr)
      b3 b4 = quad_best(bl) quad_best(br)
      pick_better(pick_better(b1, b2), pick_better(b3, b4))

# Crossover between two 32-bit integers
def crossover_uniform(+a: U32, +b: U32, +mask: U32) -> U32:
  U32.or(U32.and(a, mask), U32.and(b, U32.not(mask)))

def expand_nibble(+m: U32, +bit_idx: Nat, +shift: Nat) -> U32:
  +bit = U32.and(U32.shrn(m, bit_idx), 1)
  Bool.pick(U32, U32.is_ne(bit, 0), U32.shln(15, shift), 0)

def block_mask(+rnd: U32) -> U32:
  +m0 = expand_nibble(rnd, 0n, 0n)
  +m1 = expand_nibble(rnd, 1n, 4n)
  +m2 = expand_nibble(rnd, 2n, 8n)
  +m3 = expand_nibble(rnd, 3n, 12n)
  +m4 = expand_nibble(rnd, 4n, 16n)
  +m5 = expand_nibble(rnd, 5n, 20n)
  +m6 = expand_nibble(rnd, 6n, 24n)
  +m7 = expand_nibble(rnd, 7n, 28n)
  U32.or(m0, U32.or(m1, U32.or(m2, U32.or(m3, U32.or(m4, U32.or(m5, U32.or(m6, m7)))))))

def crossover_blocks(+a: U32, +b: U32, +rnd: U32) -> U32:
  +mask = block_mask(rnd)
  U32.or(U32.and(a, mask), U32.and(b, U32.not(mask)))

# Mutate a single bit or invert an entire 4-bit trap block
def mutate_gene(+g: U32, +rnd: U32) -> U32:
  +s1 = step(rnd)
  +mode = U32.mod(rnd, 3)
  +nibble = U32.to_nat(U32.mul(U32.mod(s1, 8), 4))
  +bit_idx = U32.to_nat(U32.mod(s1, 32))
  Bool.pick(U32, U32.is_eq(mode, 0),
    U32.xor(g, U32.shln(15, nibble)), # Invert block
    U32.xor(g, U32.shln(1, bit_idx))) # Flip bit

# Local Cellular Mating within a quadrant:
# Preserves spatial locality and allows distinct niches to emerge
def mate_and_replace(+current: Ind, +neighbor: Ind, +seed: U32) -> Ind:
  +s1 = step(seed)
  +s2 = step(s1)
  +s3 = step(s2)
  +g1 = Ind.gene(current)
  +g2 = Ind.gene(neighbor)
  # 50% block crossover, 50% uniform crossover
  +child_g = Bool.pick(U32, U32.is_zero(U32.and(s1, 1)),
    crossover_blocks(g1, g2, s2),
    crossover_uniform(g1, g2, s2))
  +mut_g = Bool.pick(U32, U32.is_lt(U32.mod(s3, 10), 4), mutate_gene(child_g, s3), child_g)
  +child = make_ind(mut_g)
  # Local replacement: replace current cell if child is better or equal
  Bool.pick(Ind, U32.is_ge(Ind.fit(child), Ind.fit(current)), child, current)

# Advance quadrant cells concurrently
def step_quad(q: QuadTree, +seed: U32) -> QuadTree:
  match q:
    case QLeaf{cell}:
      QLeaf{cell}
    case QNode{tl, tr, bl, br}:
      match tl tr bl br:
        case QLeaf{+c_tl} QLeaf{+c_tr} QLeaf{+c_bl} QLeaf{+c_br}:
          +s1 = step(seed); +s2 = step(s1); +s3 = step(s2); +s4 = step(s3)
          +new_tl = mate_and_replace(c_tl, c_tr, s1)
          +new_tr = mate_and_replace(c_tr, c_br, s2)
          +new_br = mate_and_replace(c_br, c_bl, s3)
          +new_bl = mate_and_replace(c_bl, c_tl, s4)
          QNode{QLeaf{new_tl}, QLeaf{new_tr}, QLeaf{new_bl}, QLeaf{new_br}}
        case _ _ _ _:
          s1 s2 = split.fst(seed) split.snd(seed)
          s3 s4 = split.trd(seed) split.fth(seed)
          ntl ntr = step_quad(tl, s1) step_quad(tr, s2)
          nbl nbr = step_quad(bl, s3) step_quad(br, s4)
          QNode{ntl, ntr, nbl, nbr}

# Diffuse border cells across quadrants
def diffuse_borders(q: QuadTree) -> QuadTree:
  match q:
    case QLeaf{cell}:
      QLeaf{cell}
    case QNode{tl, tr, bl, br}:
      QNode{tl, bl, tr, br}

def gen_quad(d: Nat, +seed: U32) -> QuadTree:
  match d:
    case 0n:
      QLeaf{make_ind(seed)}
    case 1n+p:
      +p = p
      +s1 = split.fst(seed); +s2 = split.snd(seed)
      +s3 = split.trd(seed); +s4 = split.fth(seed)
      q1 q2 = gen_quad(p, s1) gen_quad(p, s2)
      q3 q4 = gen_quad(p, s3) gen_quad(p, s4)
      QNode{q1, q2, q3, q4}

def run_cga(g: Nat, q: QuadTree, +seed: U32) -> QuadTree:
  match g:
    case 0n:
      q
    case 1n+p:
      +s_step = step(seed)
      +stepped = step_quad(q, seed)
      +diffused = Bool.pick(QuadTree, U32.is_zero(U32.mod(s_step, 3)), diffuse_borders(stepped), stepped)
      run_cga(p, diffused, s_step)

def main_seed() -> U32:
  987654321

def main() -> IO(Unit):
  +s0 = main_seed()
  # Depth 3 quadtree = 4^3 = 64 cells (8x8 cellular toroidal mesh)
  +mesh0 = gen_quad(3n, s0)
  +best0 = quad_best(mesh0)
  +f0 = Ind.fit(best0)

  # Run cellular evolutionary diffusion for 50 generations
  +mesh_fin = run_cga(90n, mesh0, step(s0))
  +best_fin = quad_best(mesh_fin)
  +f_fin = Ind.fit(best_fin)

  IO.print(
    "=== CENÁRIO 9: CELLULAR GENETIC ALGORITHM (cGA / QUAD-TREE) ===\n" ++
    "Topologia: Grade Espacial 2D 8x8 (64 células em Quad-Tree Paralela)\n" ++
    "Problema: Deceptive 4-Bit Trap (8 blocos x 4 bits = 32 bits enganosos)\n" ++
    "  Armadilha local: Fitness 24 (todos zeros atraem gradiente)\n" ++
    "  Ótimo global:    Fitness 32 (todos uns requerem nichos e diversidade)\n" ++
    "Geração 0  - Melhor Fitness: " ++ U32.show(f0) ++ " / 32\n" ++
    "Geração 90 - Melhor Fitness: " ++ U32.show(f_fin) ++ " / 32\n" ++
    "Escapou da Armadilha e Atingiu Ótimo Global? " ++ Bool.show(U32.is_eq(f_fin, 32)) ++ "\n"
  )
