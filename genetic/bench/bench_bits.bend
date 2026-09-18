import Base
import ./../ga.bend as GA
import ./../operators.bend as Op
import ./../utils/bits.bend as B
import ./../utils/random.bend as R

# ================================================================
# BENCHMARK: CARGA PESADA SOBRE GENOMAS BINARIOS (Royal Road)
# ================================================================
# 8 ilhas x 64 individuos x 20 epocas x 250 geracoes.
# Exercita operators.bend Secao B e o motor sobre U32.
# ================================================================

# Royal Road: bonus por bloco de 8 bits completo, alem do popcount
def block_bonus(+bits: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.and(bits, 255), 255), 50, 0)

def fitness(g: U32) -> U32:
  +g = g
  (B.popcount(g)
   + block_bonus(g) + block_bonus(U32.shrn(g, 8n))
   + block_bonus(U32.shrn(g, 16n)) + block_bonus(U32.shrn(g, 24n)) : U32)

def init_gene(seed: U32) -> U32:
  R.step(seed)

def mut_rr(g: U32, seed: U32) -> U32:
  Op.combine_mutations(~U32, ~Op.mut_bit_flip32, ~Op.mut_bits_invert_block, 70, g, seed)

def reproduce(parent: U32, champ: U32, seed: U32) -> U32:
  Op.pipe_rated(~U32, ~Op.cross_bits_2point, ~mut_rr, 90, 90, parent, champ, seed)

def main() -> IO(Unit):
  +s0 = {87654321 : U32}
  +arch0 = GA.gen_archipelago(~U32, ~init_gene, ~fitness, 3n, s0, 6n)
  +arch_fin = GA.run_archipelago(~U32, ~reproduce, ~fitness, 20n, arch0, R.step(s0), 250n)
  +champ = GA.best_archipelago(U32, arch_fin)
  IO.print("bench_bits | melhor aptidao: " ++ U32.show(GA.Ind.fit(U32, champ)) ++ "\n")
