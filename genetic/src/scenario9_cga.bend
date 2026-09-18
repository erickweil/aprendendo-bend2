import Base
import ./../utils/cga.bend as CGA
import ./../utils/random.bend as R
import ./../utils/bits.bend as B

# ================================================================
# CENÁRIO 9: CELLULAR GENETIC ALGORITHM (cGA / QUAD-TREE)
# COM MOTOR CELULAR GENÉRICO
# ================================================================
# Topologia: Grade Espacial 2D 8x8 (64 células em Quad-Tree)
# Problema: Deceptive 4-Bit Trap (8 blocos x 4 bits = 32 bits)
#   Armadilha local: Fitness 24 (zeros atraem a busca tradicional)
#   Ótimo global:    Fitness 32 (uns requerem preservação de nichos)
# ================================================================

# Deceptive 4-Bit Trap Function
def trap4(+bits: U32) -> U32:
  +c = B.popcount(U32.and(bits, 15))
  Bool.pick(U32, U32.is_eq(c, 4), 4,
    Bool.pick(U32, U32.is_eq(c, 0), 3,
      Bool.pick(U32, U32.is_eq(c, 1), 2,
        Bool.pick(U32, U32.is_eq(c, 2), 1, 0))))

# 8 armadilhas concatenadas = 32 bits
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

def make_ind(+gene: U32) -> Ind:
  Ind{gene, eval_deceptive_trap(gene)}

def Ind.gene(i: Ind) -> U32:
  Ind{g, _} = i
  g

def Ind.fit(i: Ind) -> U32:
  Ind{_, f} = i
  f

def pick_better(a: Ind, b: Ind) -> Ind:
  +a = a; +b = b
  Bool.pick(Ind, U32.is_ge(Ind.fit(a), Ind.fit(b)), a, b)

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
  +s1 = R.step(rnd)
  +mode = U32.mod(rnd, 3)
  +nibble = U32.to_nat(U32.mul(U32.mod(s1, 8), 4))
  +bit_idx = U32.to_nat(U32.mod(s1, 32))
  Bool.pick(U32, U32.is_eq(mode, 0),
    U32.xor(g, U32.shln(15, nibble)),
    U32.xor(g, U32.shln(1, bit_idx)))

# Acasalamento celular local dentro de um quadrante espacial
def mate_and_replace(current: Ind, neighbor: Ind, seed: U32) -> Ind:
  +current = current; +neighbor = neighbor; +seed = seed
  +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2)
  +g1 = Ind.gene(current)
  +g2 = Ind.gene(neighbor)
  +child_g = Bool.pick(U32, U32.is_zero(U32.and(s1, 1)),
    crossover_blocks(g1, g2, s2),
    B.crossover_uniform(g1, g2, s2))
  +mut_g = Bool.pick(U32, U32.is_lt(U32.mod(s3, 10), 4), mutate_gene(child_g, s3), child_g)
  +child = make_ind(mut_g)
  Bool.pick(Ind, U32.is_ge(Ind.fit(child), Ind.fit(current)), child, current)

def init_cell(seed: U32) -> Ind:
  make_ind(seed)

def main_seed() -> U32:
  987654321

def main() -> IO(Unit):
  +s0 = main_seed()
  # Profundidade 3 quadtree = 4^3 = 64 células (grade 8x8 espacial paralela)
  +mesh0 = CGA.gen_quad(~Ind, ~init_cell, 3n, s0)
  +best0 = CGA.quad_best(~Ind, ~pick_better, mesh0)
  +f0 = Ind.fit(best0)

  # 90 gerações de difusão evolutiva celular com o motor genérico
  +mesh_fin = CGA.run_cga(~Ind, ~mate_and_replace, 90n, mesh0, R.step(s0))
  +best_fin = CGA.quad_best(~Ind, ~pick_better, mesh_fin)
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
