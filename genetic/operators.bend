import Base
import ./../utils/random.bend as R
import ./../utils/math.bend as M
import ./../utils/vec4.bend as V

import ./utils/bits.bend as B

# ================================================================
# BEND 2 GENETIC OPERATORS LIBRARY (operators.bend)
# ================================================================
# Biblioteca unificada de operadores genéticos e combinadores
# higher-order, ao lado do motor `ga.bend`.
#
# Portada do motor original em Rust/TypeScript
# (`my-website/rust-wasm/src/genetic/operators` e
#  `my-website/src/lib/genetic/*Operators.ts`).
#
# Os combinadores usam parâmetros-template `~` (substituição em
# tempo de compilação): o operador escolhido NÃO vira uma closure
# em runtime, é inlinado no ponto de chamada. Cada combinação
# distinta gera sua própria cópia especializada — abstração de
# custo zero, verificada pelas Leis 8-11 em LAWS.bend / PROOF.bend.
# ================================================================

# ----------------------------------------------------------------
# SEÇÃO A: COMBINADORES HIGHER-ORDER (POLIMÓRFICOS SOBRE ~G)
# ----------------------------------------------------------------

# Despacho exclusivo entre duas mutações via pattern matching
# (consumo linear de `g`: apenas um dos ramos toca o genoma)
def branch_mut(~G: Type, ~m1: G -> U32 -> G, ~m2: G -> U32 -> G,
               cond: Bool, g: G, +seed: U32) -> G:
  match cond:
    case True{}:
      m1(g, seed)
    case False{}:
      m2(g, seed)

# Despacho exclusivo entre cruzar e clonar o pai 1
def branch_cross(~G: Type, ~cross: G -> G -> U32 -> G,
                 cond: Bool, p1: G, p2: G, +seed: U32) -> G:
  match cond:
    case True{}:
      cross(p1, p2, seed)
    case False{}:
      p1

# Despacho exclusivo entre mutar e preservar
def branch_maybe_mut(~G: Type, ~mut: G -> U32 -> G,
                     cond: Bool, g: G, +seed: U32) -> G:
  match cond:
    case True{}:
      mut(g, seed)
    case False{}:
      g

# Escolha probabilística entre dois operadores de mutação
# (ex.: 70% de m1 e 30% de m2 — exatamente um deles é aplicado)
def combine_mutations(~G: Type, ~m1: G -> U32 -> G, ~m2: G -> U32 -> G,
                      +pct_m1: U32, g: G, +seed: U32) -> G:
  +s1 = R.step(seed)
  +roll = U32.mod(seed, 100)
  branch_mut(~G, ~m1, ~m2, U32.is_lt(roll, pct_m1), g, s1)

# Encadeamento de dois operadores de mutação: aplica AMBOS em
# sequência com sementes independentes. Este é o equivalente fiel
# do `mutation_combine` (Rust) / `mutationCombineOperator` (TS),
# onde cada operador recebe uma fração da taxa total de mutação.
def chain_mutations(~G: Type, ~m1: G -> U32 -> G, ~m2: G -> U32 -> G,
                    g: G, +seed: U32) -> G:
  +s1 = R.split.fst(seed)
  +s2 = R.split.snd(seed)
  m2(m1(g, s1), s2)

# Aplica a mutação apenas se passar no sorteio da taxa P_m
def maybe_mutate(~G: Type, ~mut: G -> U32 -> G,
                 +rate_pct: U32, g: G, +seed: U32) -> G:
  +s1 = R.step(seed)
  +roll = U32.mod(seed, 100)
  branch_maybe_mut(~G, ~mut, U32.is_lt(roll, rate_pct), g, s1)

# Executa o crossover com probabilidade P_c; senão herda o pai 1
# intacto (reprodução clássica de Holland)
def crossover_or_clone(~G: Type, ~cross: G -> G -> U32 -> G,
                       +cross_pct: U32, p1: G, p2: G, +seed: U32) -> G:
  +s1 = R.step(seed)
  +roll = U32.mod(seed, 100)
  branch_cross(~G, ~cross, U32.is_lt(roll, cross_pct), p1, p2, s1)

# Pipeline canônico de reprodução: crossover(p1, p2) seguido de
# mutação do filho, com sementes bifurcadas independentes.
def pipe(~G: Type, ~cross: G -> G -> U32 -> G, ~mut: G -> U32 -> G,
         p1: G, p2: G, +seed: U32) -> G:
  +s1 = R.step(seed)
  +s2 = R.step(s1)
  +child = cross(p1, p2, s1)
  mut(child, s2)

# Pipeline completo com taxas (equivalente ao laço de reprodução do
# `ga.ts`: sorteia crossover_rate, depois sorteia mutation_rate)
def pipe_rated(~G: Type, ~cross: G -> G -> U32 -> G, ~mut: G -> U32 -> G,
               +cross_pct: U32, +mut_pct: U32, p1: G, p2: G, +seed: U32) -> G:
  +s1 = R.split.fst(seed)
  +s2 = R.split.snd(seed)
  +child = crossover_or_clone(~G, ~cross, cross_pct, p1, p2, s1)
  maybe_mutate(~G, ~mut, mut_pct, child, s2)

# Pipeline guloso (seleção (mu+1) da Evolução Diferencial):
# gera um vetor-teste e só o aceita se o custo não piorar.
def pipe_greedy(~G: Type, ~cost: G -> F32, ~gen: G -> G -> U32 -> G,
                target: G, champ: G, +seed: U32) -> G:
  +target = target
  +trial = gen(target, champ, seed)
  +trial = trial
  +c_trial = cost(trial)
  +c_target = cost(target)
  Bool.pick(G, F32.is_le(c_trial, c_target), trial, target)

# ----------------------------------------------------------------
# SEÇÃO B: OPERADORES PARA GENOMAS BINÁRIOS (U32)
# ----------------------------------------------------------------

# --- Crossovers ---

# Crossover uniforme: cada bit vem de p1 ou p2 conforme máscara aleatória
def cross_bits_uniform(p1: U32, p2: U32, seed: U32) -> U32:
  B.crossover_uniform(p1, p2, seed)

# Crossover uniforme restrito aos 10 bits menos significativos (Knapsack)
def cross_bits_uniform10(p1: U32, p2: U32, seed: U32) -> U32:
  U32.and(B.crossover_uniform(p1, p2, seed), 1023)

# Máscara de corte único: bits [0, k) ligados, k sorteado em [1, 31]
def mask_1point(+seed: U32) -> U32:
  +k = (1 + U32.mod(seed, 31) : U32)
  (U32.shln(1, U32.to_nat(k)) - 1 : U32)

# Máscara de corte duplo: bits [k1, k2) ligados, 1 <= k1 < k2 <= 31
def mask_2point(+seed: U32) -> U32:
  +s1 = R.step(seed)
  +k1 = (1 + U32.mod(seed, 30) : U32)
  +k1 = k1
  +k2 = (k1 + 1 + U32.mod(s1, (31 - k1 : U32)) : U32)
  +m1 = (U32.shln(1, U32.to_nat(k1)) - 1 : U32)
  +m2 = (U32.shln(1, U32.to_nat(k2)) - 1 : U32)
  U32.xor(m1, m2)

# Single-Point Crossover em 32 bits
def cross_bits_1point(p1: U32, p2: U32, seed: U32) -> U32:
  B.crossover_uniform(p1, p2, mask_1point(seed))

# Two-Point Crossover em 32 bits (preserva o segmento interno)
def cross_bits_2point(p1: U32, p2: U32, seed: U32) -> U32:
  B.crossover_uniform(p1, p2, mask_2point(seed))

# --- Mutações ---

# Flip pontual de 1 bit aleatório em [0, 31]
def mut_bit_flip32(g: U32, seed: U32) -> U32:
  B.mutate_bit(g, seed)

# Flip pontual de 1 bit aleatório em [0, 9] (genomas de 10 itens)
def mut_bit_flip10(g: U32, seed: U32) -> U32:
  +bit = U32.to_nat(U32.mod(seed, 10))
  U32.xor(g, U32.shln(1, bit))

# Laço interno da mutação bit-a-bit (fuel = bits restantes)
def mut_bits_multi_go(n: Nat, +g: U32, +rate_pct: U32, +seed: U32, +bit: U32) -> U32:
  match n:
    case 0n:
      g
    case 1n+q:
      +s = R.step(seed)
      +flip = Bool.pick(U32, R.chance(s, rate_pct), B.bit_of(bit), 0)
      mut_bits_multi_go(q, U32.xor(g, flip), rate_pct, s, U32.inc(bit))

# Muta cada um dos 32 bits independentemente com probabilidade rate_pct%
def mut_bits_multi(+rate_pct: U32, g: U32, seed: U32) -> U32:
  mut_bits_multi_go(32n, g, rate_pct, seed, 0)

# Inversão lógica de um bloco contíguo de 8 bits (1 dos 4 bytes)
def mut_bits_invert_block(g: U32, seed: U32) -> U32:
  +blk = U32.to_nat(U32.mul(U32.mod(seed, 4), 8))
  U32.xor(g, U32.shln(255, blk))

# Troca de posição de dois blocos de 8 bits (macro-mutação de building blocks)
def mut_bits_swap_blocks(g: U32, seed: U32) -> U32:
  +g = g
  +seed = seed
  +b1 = U32.mod(seed, 4)
  +b2 = U32.mod(R.step(seed), 4)
  +sh1 = U32.to_nat(U32.mul(b1, 8))
  +sh2 = U32.to_nat(U32.mul(b2, 8))
  +sh1 = sh1
  +sh2 = sh2
  +v1 = U32.and(U32.shrn(g, sh1), 255)
  +v2 = U32.and(U32.shrn(g, sh2), 255)
  +g_clean1 = U32.and(g, U32.not(U32.shln(255, sh1)))
  +g_clean2 = U32.and(g_clean1, U32.not(U32.shln(255, sh2)))
  U32.or(g_clean2, U32.or(U32.shln(v2, sh1), U32.shln(v1, sh2)))

# Troca a posição de 2 bits sorteados (preserva o popcount do genoma)
def mut_bits_swap(g: U32, seed: U32) -> U32:
  +g = g
  +g = g
  +seed = seed
  +s1 = R.step(seed)
  +b1 = U32.to_nat(U32.mod(seed, 32))
  +b2 = U32.to_nat(U32.mod(s1, 32))
  +v1 = U32.and(U32.shrn(g, b1), 1)
  +v2 = U32.and(U32.shrn(g, b2), 1)
  +diff = U32.xor(v1, v2)
  +flip_mask = U32.or(U32.shln(diff, b1), U32.shln(diff, b2))
  U32.xor(g, flip_mask)

# ----------------------------------------------------------------
# SEÇÃO D: OPERADORES CONTÍNUOS (F32 / Vec4)
# ----------------------------------------------------------------

# Crossover uniforme escalar: herda w1 ou w2 com 50% cada
def cross_f32_uniform(+w1: F32, +w2: F32, +rnd: U32) -> F32:
  Bool.pick(F32, R.chance(rnd, 50), w1, w2)

# Crossover aritmético escalar: combinação linear w1 + (w2 - w1) * alpha
def cross_f32_arith(+w1: F32, +w2: F32, +alpha: F32) -> F32:
  F32.lerp(w1, w2, alpha)

# Mutação escalar com ruído contínuo: com rate_pct% de chance soma
# um jitter uniforme em [-scale, +scale]
def mut_f32_jitter(+rate_pct: U32, +scale: F32, +w: F32, +seed: U32) -> F32:
  +should = R.chance(seed, rate_pct)
  +jitter = (M.rnd_unit(R.step(seed)) * scale : F32)
  Bool.pick(F32, should, (w + jitter : F32), w)

# Passo de Evolução Diferencial por coordenada (DE/current-to-best):
# 25% exploração pura, 75% atração pelo campeão com ruído proporcional
def de_step_coord(+target: F32, +champ: F32, +rnd: U32) -> F32:
  +target = target
  +diff = (champ - target : F32)
  +diff = diff
  +jitter = M.rnd_unit_coarse(rnd)
  +jitter = jitter
  Bool.pick(F32, R.chance(rnd, 25),
    (target + ({0.5 : F32} * jitter) : F32),
    (target + ({0.7 : F32} * diff) + ({0.15 : F32} * jitter * F32.abs(diff)) : F32))

# Crossover uniforme por coordenada em R^4
def cross_vec4_uniform(v1: V.Vec4, v2: V.Vec4, seed: U32) -> V.Vec4:
  V.Vec4{a0, a1, a2, a3} = v1
  V.Vec4{b0, b1, b2, b3} = v2
  +s0 = R.step(seed)
  +s1 = R.step(s0)
  +s2 = R.step(s1)
  +s3 = R.step(s2)
  V.Vec4{
    cross_f32_uniform(a0, b0, s0),
    cross_f32_uniform(a1, b1, s1),
    cross_f32_uniform(a2, b2, s2),
    cross_f32_uniform(a3, b3, s3)
  }

# Crossover aritmético (combinação linear contínua) com alpha sorteado
def cross_vec4_arithmetic(v1: V.Vec4, v2: V.Vec4, seed: U32) -> V.Vec4:
  V.Vec4{a0, a1, a2, a3} = v1
  V.Vec4{b0, b1, b2, b3} = v2
  +alpha = M.rnd_norm(seed, 1000)
  V.Vec4{
    cross_f32_arith(a0, b0, alpha),
    cross_f32_arith(a1, b1, alpha),
    cross_f32_arith(a2, b2, alpha),
    cross_f32_arith(a3, b3, alpha)
  }

# Perturbação vetorial de Evolução Diferencial com crossover por coordenada
def cross_vec4_differential(target: V.Vec4, champ: V.Vec4, seed: U32) -> V.Vec4:
  V.Vec4{tx0, tx1, tx2, tx3} = target
  V.Vec4{cx0, cx1, cx2, cx3} = champ
  +s0 = R.step(seed)
  +s1 = R.step(s0)
  +s2 = R.step(s1)
  +s3 = R.step(s2)
  V.Vec4{
    de_step_coord(tx0, cx0, s0),
    de_step_coord(tx1, cx1, s1),
    de_step_coord(tx2, cx2, s2),
    de_step_coord(tx3, cx3, s3)
  }

# Perturbação estocástica com ruído contínuo em R^4
def mut_vec4_jitter(+rate_pct: U32, +scale: F32, v: V.Vec4, +seed: U32) -> V.Vec4:
  V.Vec4{x0, x1, x2, x3} = v
  +s0 = R.step(seed)
  +s1 = R.step(s0)
  +s2 = R.step(s1)
  +s3 = R.step(s2)
  V.Vec4{
    mut_f32_jitter(rate_pct, scale, x0, s0),
    mut_f32_jitter(rate_pct, scale, x1, s1),
    mut_f32_jitter(rate_pct, scale, x2, s2),
    mut_f32_jitter(rate_pct, scale, x3, s3)
  }
