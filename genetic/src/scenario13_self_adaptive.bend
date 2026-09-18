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

# Paisagem Royal Road (Holland & Mitchell 1992):
# 4 blocos de 8 bits. Cada bloco de 8 uns completos dá 250 pontos.
def royal_block(+bits: U32) -> U32:
  +ones = popcount(U32.and(bits, 255))
  Bool.pick(U32, U32.is_eq(ones, 8), 250, 0)

def royal_road(+gene: U32) -> U32:
  +b0 = royal_block(gene)
  +b1 = royal_block(U32.shrn(gene, 8n))
  +b2 = royal_block(U32.shrn(gene, 16n))
  +b3 = royal_block(U32.shrn(gene, 24n))
  (b0 + b1 + b2 + b3 : U32)

def eval_fitness(+gene: U32) -> U32:
  +rr = royal_road(gene)
  +guide = U32.mul(popcount(gene), 2)
  (rr + guide : U32)

# Indivíduo com Hiperparâmetros Auto-Adaptativos no Genoma
# gene: cromossomo do problema (32 bits)
# rate: taxa de mutação adaptativa (1..10)
# op:   operador adaptativo (0 = bitflip, 1 = swap de blocos, 2 = inversão de segmento)
# fit:  aptidão
type SAInd is Data:
  SAInd{gene: U32, rate: U32, op: U32, fit: U32}

def make_saind(+gene: U32, +rate: U32, +op: U32) -> SAInd:
  SAInd{gene, rate, op, eval_fitness(gene)}

def SAInd.gene(i: SAInd) -> U32:
  SAInd{g, _, _, _} = i
  g

def SAInd.rate(i: SAInd) -> U32:
  SAInd{_, r, _, _} = i
  r

def SAInd.op(i: SAInd) -> U32:
  SAInd{_, _, o, _} = i
  o

def SAInd.fit(i: SAInd) -> U32:
  SAInd{_, _, _, f} = i
  f

# Árvore Populacional Binária
type SATree is Data:
  SALeaf{ind: SAInd}
  SANode{left: SATree, right: SATree}

def pick_better_saind(+a: SAInd, +b: SAInd) -> SAInd:
  Bool.pick(SAInd, U32.is_ge(SAInd.fit(a), SAInd.fit(b)), a, b)

def best_saind(t: SATree) -> SAInd:
  match t:
    case SALeaf{ind}:
      ind
    case SANode{left, right}:
      bl br = best_saind(left) best_saind(right)
      pick_better_saind(bl, br)

# Média de taxa de mutação na população (redução em árvore)
def sum_rate(t: SATree) -> U32:
  match t:
    case SALeaf{ind}:
      SAInd.rate(ind)
    case SANode{left, right}:
      sl sr = sum_rate(left) sum_rate(right)
      (sl + sr : U32)

def gen_saind_pop(d: Nat, +seed: U32) -> SATree:
  match d:
    case 0n:
      +s1 = step(seed); +s2 = step(s1)
      +init_rate = (1 + U32.mod(s1, 10) : U32)
      +init_op = U32.mod(s2, 3)
      SALeaf{make_saind(seed, init_rate, init_op)}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_saind_pop(p, split.fst(seed)) gen_saind_pop(p, split.snd(seed))
      SANode{l, r}

def crossover_uniform(+a: U32, +b: U32, +mask: U32) -> U32:
  U32.or(U32.and(a, mask), U32.and(b, U32.not(mask)))

# Mutação de taxa adaptativa (passo estocástico +-1 com limites [1, 10])
def mutate_rate(+r: U32, +rnd: U32) -> U32:
  +delta = Bool.pick(U32, U32.is_zero(U32.and(rnd, 1)), 1, 0)
  +add_flag = U32.is_zero(U32.and(U32.shrn(rnd, 1n), 1))
  +new_r = Bool.pick(U32, add_flag, (r + delta : U32),
             Bool.pick(U32, U32.is_gt(r, delta), (r - delta : U32), 1))
  Bool.pick(U32, U32.is_lt(new_r, 1), 1,
    Bool.pick(U32, U32.is_gt(new_r, 10), 10, new_r))

# Operador 1: Swap de dois blocos de 8 bits
def swap_blocks(+g: U32, +rnd: U32) -> U32:
  +b1 = U32.mod(rnd, 4)
  +b2 = U32.mod(step(rnd), 4)
  +sh1 = U32.to_nat(U32.mul(b1, 8))
  +sh2 = U32.to_nat(U32.mul(b2, 8))
  +v1 = U32.and(U32.shrn(g, sh1), 255)
  +v2 = U32.and(U32.shrn(g, sh2), 255)
  +g_clean1 = U32.and(g, U32.not(U32.shln(255, sh1)))
  +g_clean2 = U32.and(g_clean1, U32.not(U32.shln(255, sh2)))
  U32.or(g_clean2, U32.or(U32.shln(v2, sh1), U32.shln(v1, sh2)))

# Operador 2: Inversão de um bloco de 8 bits
def invert_block(+g: U32, +rnd: U32) -> U32:
  +blk = U32.to_nat(U32.mul(U32.mod(rnd, 4), 8))
  U32.xor(g, U32.shln(255, blk))

# Operador 0: Flip de bit pontual
def flip_bit(+g: U32, +rnd: U32) -> U32:
  +bit_idx = U32.to_nat(U32.mod(rnd, 32))
  U32.xor(g, U32.shln(1, bit_idx))

# Aplica a mutação genética usando os parâmetros auto-adaptados do próprio indivíduo
def apply_adaptive_mutation(+g: U32, +rate: U32, +op: U32, +rnd: U32) -> U32:
  +s1 = step(rnd); +s2 = step(s1)
  # O indivíduo só sofre mutação se passar no seu próprio limiar adaptado rate / 10
  +should_mutate = U32.is_lt(U32.mod(rnd, 10), rate)
  Bool.pick(U32, should_mutate,
    Bool.pick(U32, U32.is_eq(op, 0), flip_bit(g, s1),
      Bool.pick(U32, U32.is_eq(op, 1), swap_blocks(g, s1), invert_block(g, s1))),
    g)

# Reprodução Auto-Adaptativa
def reproduce_saind(tree: SATree, +seed: U32, +elite: SAInd) -> SATree:
  match tree:
    case SALeaf{+ind}:
      +s1 = step(seed); +s2 = step(s1); +s3 = step(s2); +s4 = step(s3)
      +g_ind = SAInd.gene(ind)
      +g_elt = SAInd.gene(elite)
      +r_ind = SAInd.rate(ind)
      +r_elt = SAInd.rate(elite)
      +o_ind = SAInd.op(ind)
      +o_elt = SAInd.op(elite)

      # 1. Cruzamento do cromossomo do problema e dos parâmetros de busca
      +crossed_g = crossover_uniform(g_ind, g_elt, s1)
      +child_rate = Bool.pick(U32, U32.is_zero(U32.and(s2, 1)), r_ind, r_elt)
      +child_op   = Bool.pick(U32, U32.is_zero(U32.and(s2, 2)), o_ind, o_elt)

      # 2. Auto-mutação dos parâmetros de busca
      +mut_rate = mutate_rate(child_rate, s3)
      +mut_op   = Bool.pick(U32, U32.is_lt(U32.mod(s3, 10), 2), U32.mod(s4, 3), child_op)

      # 3. Mutação do cromossomo com a taxa e operador adaptados
      +final_g = apply_adaptive_mutation(crossed_g, mut_rate, mut_op, s4)
      +child = make_saind(final_g, mut_rate, mut_op)
      SALeaf{pick_better_saind(child, ind)}
    case SANode{left, right}:
      +seed = seed
      +elite = elite
      l r = reproduce_saind(left, split.fst(seed), elite) reproduce_saind(right, split.snd(seed), elite)
      SANode{l, r}

def step_gen(+tree: SATree, +seed: U32) -> SATree:
  +best = best_saind(tree)
  reproduce_saind(tree, seed, best)

def run_self_adaptive(g: Nat, tree: SATree, +seed: U32) -> SATree:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = step(seed)
      +next_tree = step_gen(tree, seed)
      run_self_adaptive(p, next_tree, next_seed)

def op_name(+op: U32) -> String:
  Bool.pick(String, U32.is_eq(op, 0), "Bit-Flip",
    Bool.pick(String, U32.is_eq(op, 1), "Block-Swap", "Segment-Inversion"))

def main_seed() -> U32:
  55443322

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 64 indivíduos auto-adaptativos em árvore binária paralela
  +pop0 = gen_saind_pop(6n, s0)
  +best0 = best_saind(pop0)
  +f0 = SAInd.fit(best0)
  +r0 = SAInd.rate(best0)
  +o0 = SAInd.op(best0)
  +avg_r0 = U32.div(sum_rate(pop0), 64)

  # Evoluir por 70 gerações
  +pop_fin = run_self_adaptive(70n, pop0, step(s0))
  +best_fin = best_saind(pop_fin)
  +f_fin = SAInd.fit(best_fin)
  +r_fin = SAInd.rate(best_fin)
  +o_fin = SAInd.op(best_fin)
  +avg_r_fin = U32.div(sum_rate(pop_fin), 64)
  +rr_blocks = U32.div(royal_road(SAInd.gene(best_fin)), 250)

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
