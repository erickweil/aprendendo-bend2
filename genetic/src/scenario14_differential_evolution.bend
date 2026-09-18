import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R

# ================================================================
# CENÁRIO 14: EVOLUÇÃO DIFERENCIAL CONTÍNUA (DE / RASTRIGIN 4D)
# COM MOTOR GENÉRICO
# ================================================================
# Espaço de Busca: R^4 em [-5.0, 5.0]^4 (Otimização Numérica com F32)
# Função Objetivo: Rastrigin 4D (Multi-Modal com Dezenas de Mínimos Locais)
# Mínimo Global Teórico: 0.0 na origem (0.0, 0.0, 0.0, 0.0)
# ================================================================

# Vetor Contínuo 4D em R^4
type Vec4 is Data:
  Vec4{x0: F32, x1: F32, x2: F32, x3: F32}

def make_vec4(+x0: F32, +x1: F32, +x2: F32, +x3: F32) -> Vec4:
  Vec4{x0, x1, x2, x3}

# Componente 1D da função Rastrigin: x^2 - 10*cos(2*pi*x) + 10
def rastrigin_1d(+x: F32) -> F32:
  +two_pi = (2.0 * F32.pi() : F32)
  +cos_val = F32.cos((two_pi * x : F32))
  ((x * x) - (10.0 * cos_val) + 10.0 : F32)

# Função Rastrigin 4D (Ótimo Global = 0.0 na origem (0.0, 0.0, 0.0, 0.0))
def eval_rastrigin(v: Vec4) -> F32:
  Vec4{x0, x1, x2, x3} = v
  (rastrigin_1d(x0) + rastrigin_1d(x1) + rastrigin_1d(x2) + rastrigin_1d(x3) : F32)

# Fitness para maximização no motor genérico: inverso do custo Rastrigin
def fitness(v: Vec4) -> U32:
  +c = eval_rastrigin(v)
  Bool.pick(U32, F32.is_lt(c, 1000.0),
    F32.to_u32(((1000.0 - c) * 100.0 : F32)),
    0)

# Amostra um float em [-5.0, 5.0] a partir de uma semente U32
def rnd_coord(+seed: U32) -> F32:
  +val = U32.to_f32(U32.mod(seed, 10000))
  +norm = (val / 10000.0 : F32)
  ((norm * 10.0) - 5.0 : F32)

def gen_rand_vec(seed: U32) -> Vec4:
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2)
  make_vec4(rnd_coord(s0), rnd_coord(s1), rnd_coord(s2), rnd_coord(s3))

# Passo de Evolução Diferencial (DE/current-to-best com perturbação proporcional)
def de_step_coord(+target: F32, +champ: F32, +rnd: U32) -> F32:
  +diff = (champ - target : F32)
  +jitter = ((U32.to_f32(U32.mod(rnd, 200)) / 100.0 : F32) - 1.0 : F32)
  Bool.pick(F32, R.chance(rnd, 25),
    (target + (0.5 * jitter) : F32),
    (target + (0.7 * diff) + (0.15 * jitter * F32.abs(diff)) : F32))

def mutate_and_cross(target: Vec4, champ: Vec4, +seed: U32) -> Vec4:
  Vec4{tx0, tx1, tx2, tx3} = target
  Vec4{cx0, cx1, cx2, cx3} = champ
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2)
  make_vec4(
    de_step_coord(tx0, cx0, s0),
    de_step_coord(tx1, cx1, s1),
    de_step_coord(tx2, cx2, s2),
    de_step_coord(tx3, cx3, s3)
  )

def reproduce(target: Vec4, champ: Vec4, seed: U32) -> Vec4:
  +target = target
  +trial = mutate_and_cross(target, champ, seed)
  +target = target
  +trial = trial
  +c_trial = eval_rastrigin(trial)
  +c_target = eval_rastrigin(target)
  Bool.pick(Vec4, F32.is_le(c_trial, c_target), trial, target)

def Vec4.show(v: Vec4) -> String:
  Vec4{x0, x1, x2, x3} = v
  "(" ++ F32.show(x0) ++ ", " ++ F32.show(x1) ++ ", " ++ F32.show(x2) ++ ", " ++ F32.show(x3) ++ ")"

def main_seed() -> U32:
  31415926

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 64 vetores contínuos em R^4 na árvore de população
  +pop0 = GA.gen_population(~Vec4, ~gen_rand_vec, ~fitness, 6n, s0)
  +best0 = GA.best_ind(Vec4, pop0)
  +v0 = GA.Ind.gene(Vec4, best0)
  +c0 = eval_rastrigin(v0)

  # Executar 80 gerações de Evolução Diferencial com motor genérico
  +pop_fin = GA.run_generations(~Vec4, ~reproduce, ~fitness, 80n, pop0, 12345)
  +best_fin = GA.best_ind(Vec4, pop_fin)
  +v_fin = GA.Ind.gene(Vec4, best_fin)
  +c_fin = eval_rastrigin(v_fin)

  IO.print(
    "=== CENÁRIO 14: EVOLUÇÃO DIFERENCIAL CONTÍNUA (DE / RASTRIGIN 4D) ===\n" ++
    "Espaço de Busca: R^4 em [-5.0, 5.0]^4 (Otimização Numérica com F32)\n" ++
    "Função Objetivo: Benchmark Rastrigin 4D (Multi-Modal com Dezenas de Mínimos Locais)\n" ++
    "Mínimo Global Teórico: 0.0 na origem (0.0, 0.0, 0.0, 0.0)\n" ++
    "População: 64 vetores contínuos (Árvore Binária Profundidade 6)\n" ++
    "Módulos da Lib Utilizados: genetic/utils/random.bend e motor ga.bend\n\n" ++
    "Geração 0  - Custo Mínimo: " ++ F32.show(c0) ++ " | Vetor: " ++ Vec4.show(v0) ++ "\n" ++
    "Geração 80 - Custo Mínimo: " ++ F32.show(c_fin) ++ " | Vetor: " ++ Vec4.show(v_fin) ++ "\n\n" ++
    "Convergência Bem-Sucedida (Custo < 2.0 em Paisagem Multi-Modal)? " ++
    Bool.show(F32.is_lt(c_fin, 2.0)) ++ "\n"
  )
