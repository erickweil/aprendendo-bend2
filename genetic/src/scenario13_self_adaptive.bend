import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../utils/bits.bend as B
import ./../utils/poptree.bend as T
import ./../operators.bend as Op

# ================================================================
# CENÁRIO 13: MOTOR EVOLUTIVO AUTO-ADAPTATIVO (SELF-ADAPTIVE GA)
# COM MOTOR GENÉRICO
# ================================================================
# Conceito: Hiperparâmetros (taxa de mutação e operador) codificados
# no próprio genoma individual.
# Paisagem: Royal Road de Holland & Mitchell (4 blocos de 8 bits = 1000 pts).
# ================================================================

type SAGene is Data:
  SAGene{gene: U32, rate: U32, op: U32}

def SAGene.gene(g: SAGene) -> U32:
  SAGene{code, _, _} = g
  code

def SAGene.rate(g: SAGene) -> U32:
  SAGene{_, r, _} = g
  r

def SAGene.op(g: SAGene) -> U32:
  SAGene{_, _, o} = g
  o

# Paisagem Royal Road (Holland & Mitchell 1992):
# 4 blocos de 8 bits. Cada bloco de 8 uns completos dá 250 pontos.
def royal_block(+bits: U32) -> U32:
  +ones = B.popcount(U32.and(bits, 255))
  Bool.pick(U32, U32.is_eq(ones, 8), 250, 0)

def royal_road(+gene: U32) -> U32:
  +b0 = royal_block(gene)
  +b1 = royal_block(U32.shrn(gene, 8n))
  +b2 = royal_block(U32.shrn(gene, 16n))
  +b3 = royal_block(U32.shrn(gene, 24n))
  (b0 + b1 + b2 + b3 : U32)

def eval_fitness(+gene: U32) -> U32:
  +rr = royal_road(gene)
  +guide = U32.mul(B.popcount(gene), 2)
  (rr + guide : U32)

def fitness(g: SAGene) -> U32:
  SAGene{gene, _, _} = g
  eval_fitness(gene)

def init_gene(seed: U32) -> SAGene:
  +seed = seed
  +s1 = R.step(seed); +s2 = R.step(s1)
  +init_rate = (1 + U32.mod(s1, 10) : U32)
  +init_op = U32.mod(s2, 3)
  SAGene{seed, init_rate, init_op}

# Mutação de taxa adaptativa (passo estocástico +-1 com limites [1, 10])
def mutate_rate(+r: U32, +rnd: U32) -> U32:
  +delta = Bool.pick(U32, U32.is_zero(U32.and(rnd, 1)), 1, 0)
  +add_flag = U32.is_zero(U32.and(U32.shrn(rnd, 1n), 1))
  +new_r = Bool.pick(U32, add_flag, (r + delta : U32),
             Bool.pick(U32, U32.is_gt(r, delta), (r - delta : U32), 1))
  Bool.pick(U32, U32.is_lt(new_r, 1), 1,
    Bool.pick(U32, U32.is_gt(new_r, 10), 10, new_r))

# Os três operadores sobre os quais o indivíduo pode se auto-adaptar vêm
# diretamente da biblioteca operators.bend:
#   op 0 -> Op.mut_bit_flip32        (flip pontual de 1 bit)
#   op 1 -> Op.mut_bits_swap_blocks  (troca de dois blocos de 8 bits)
#   op 2 -> Op.mut_bits_invert_block (inversão de um bloco de 8 bits)

# Aplica a mutação genética usando os parâmetros auto-adaptados do próprio indivíduo
def apply_adaptive_mutation(+g: U32, +rate: U32, +op: U32, +rnd: U32) -> U32:
  +s1 = R.step(rnd); +s2 = R.step(s1)
  +should_mutate = U32.is_lt(U32.mod(rnd, 10), rate)
  Bool.pick(U32, should_mutate,
    Bool.pick(U32, U32.is_eq(op, 0), Op.mut_bit_flip32(g, s1),
      Bool.pick(U32, U32.is_eq(op, 1), Op.mut_bits_swap_blocks(g, s1),
                                       Op.mut_bits_invert_block(g, s1))),
    g)

def reproduce(parent: SAGene, champ: SAGene, seed: U32) -> SAGene:
  SAGene{g_ind, r_ind, o_ind} = parent
  SAGene{g_elt, r_elt, o_elt} = champ
  +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)

  +crossed_g = Op.cross_bits_uniform(g_ind, g_elt, s1)
  +child_rate = Bool.pick(U32, U32.is_zero(U32.and(s2, 1)), r_ind, r_elt)
  +child_op   = Bool.pick(U32, U32.is_zero(U32.and(s2, 2)), o_ind, o_elt)

  +mut_rate = mutate_rate(child_rate, s3)
  +mut_op   = Bool.pick(U32, U32.is_lt(U32.mod(s3, 10), 2), U32.mod(s4, 3), child_op)

  +final_g = apply_adaptive_mutation(crossed_g, mut_rate, mut_op, s4)
  SAGene{final_g, mut_rate, mut_op}

def sum_rate(t: T.PopTree<GA.Ind<SAGene>>) -> U32:
  match t:
    case T.Leaf{ind}:
      SAGene.rate(GA.Ind.gene(SAGene, ind))
    case T.Node{left, right}:
      +sl = sum_rate(left)
      +sr = sum_rate(right)
      (sl + sr : U32)

def op_name(+op: U32) -> String:
  Bool.pick(String, U32.is_eq(op, 0), "Bit-Flip",
    Bool.pick(String, U32.is_eq(op, 1), "Block-Swap", "Segment-Inversion"))

def main_seed() -> U32:
  55443322

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 64 indivíduos auto-adaptativos em árvore binária paralela
  +pop0 = GA.gen_population(~SAGene, ~init_gene, ~fitness, 6n, s0)
  +best0 = GA.best_ind(SAGene, pop0)
  +f0 = GA.Ind.fit(SAGene, best0)
  +g0 = GA.Ind.gene(SAGene, best0)
  +r0 = SAGene.rate(g0)
  +o0 = SAGene.op(g0)
  +avg_r0 = U32.div(sum_rate(pop0), 64)

  # Evoluir por 70 gerações com o motor genérico
  +pop_fin = GA.run_generations(~SAGene, ~reproduce, ~fitness, 70n, pop0, R.step(s0))
  +best_fin = GA.best_ind(SAGene, pop_fin)
  +f_fin = GA.Ind.fit(SAGene, best_fin)
  +g_fin = GA.Ind.gene(SAGene, best_fin)
  +g_code = SAGene.gene(g_fin)
  +r_fin = SAGene.rate(g_fin)
  +o_fin = SAGene.op(g_fin)
  +avg_r_fin = U32.div(sum_rate(pop_fin), 64)
  +rr_blocks = U32.div(royal_road(g_code), 250)

  IO.print(
    "=== CENÁRIO 13: MOTOR EVOLUTIVO AUTO-ADAPTATIVO (SELF-ADAPTIVE GA) ===\n" ++
    "Conceito: Hiperparâmetros (taxa de mutação e operador) codificados no próprio genoma\n" ++
    "Paisagem: Royal Road de Holland & Mitchell (4 blocos de 8 bits = 1000 pts no platô)\n" ++
    "População: 64 indivíduos com auto-adaptação estocástica contínua\n\n" ++
    "-- GERAÇÃO 0 (Inicial) --\n" ++
    "  Melhor Aptidão: " ++ U32.show(f0) ++ " / 1064\n" ++
    "  Taxa Mutação Campeão: " ++ U32.show(r0) ++ "/10 | Operador: " ++ op_name(o0) ++ "\n" ++
    "  Taxa Média da População: " ++ U32.show(avg_r0) ++ "/10\n\n" ++
    "-- GERAÇÃO 70 (Convergência com Adaptação Dinâmica) --\n" ++
    "  Melhor Aptidão: " ++ U32.show(f_fin) ++ " / 1064\n" ++
    "  Blocos Royal Road Completos: " ++ U32.show(rr_blocks) ++ " / 4\n" ++
    "  Taxa Mutação Campeão: " ++ U32.show(r_fin) ++ "/10 | Operador: " ++ op_name(o_fin) ++ "\n" ++
    "  Taxa Média da População: " ++ U32.show(avg_r_fin) ++ "/10\n\n" ++
    "Todos os 4 Blocos Royal Road Resolvidos (1000 pts)? " ++ Bool.show(U32.is_ge(f_fin, 1000)) ++ "\n"
  )
