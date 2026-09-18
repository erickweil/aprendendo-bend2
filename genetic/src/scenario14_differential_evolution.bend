import Base
import ./../ga.bend as GA
import ./../utils/vec4.bend as V
import ./../operators.bend as Op

# ================================================================
# CENÁRIO 14: EVOLUÇÃO DIFERENCIAL CONTÍNUA (DE / RASTRIGIN 4D)
# COM MOTOR GENÉRICO
# ================================================================
# Espaço de Busca: R^4 em [-5.0, 5.0]^4 (Otimização Numérica com F32)
# Função Objetivo: Rastrigin 4D (Multi-Modal com Dezenas de Mínimos Locais)
# Mínimo Global Teórico: 0.0 na origem (0.0, 0.0, 0.0, 0.0)
# ================================================================

# O vetor contínuo 4D (`V.Vec4`) foi extraído para genetic/utils/vec4.bend
# e os operadores contínuos para a Seção D de genetic/operators.bend.

# Componente 1D da função Rastrigin: x^2 - 10*cos(2*pi*x) + 10
def rastrigin_1d(+x: F32) -> F32:
  +two_pi = (2.0 * F32.pi() : F32)
  +cos_val = F32.cos((two_pi * x : F32))
  ((x * x) - (10.0 * cos_val) + 10.0 : F32)

# Função Rastrigin 4D (Ótimo Global = 0.0 na origem (0.0, 0.0, 0.0, 0.0))
def eval_rastrigin(v: V.Vec4) -> F32:
  V.Vec4{x0, x1, x2, x3} = v
  (rastrigin_1d(x0) + rastrigin_1d(x1) + rastrigin_1d(x2) + rastrigin_1d(x3) : F32)

# Fitness para maximização no motor genérico: inverso do custo Rastrigin
def fitness(v: V.Vec4) -> U32:
  +c = eval_rastrigin(v)
  Bool.pick(U32, F32.is_lt(c, 1000.0),
    F32.to_u32(((1000.0 - c) * 100.0 : F32)),
    0)

# População inicial: vetores uniformes no hipercubo [-5.0, 5.0]^4
def gen_rand_vec(seed: U32) -> V.Vec4:
  V.rnd_vec4(seed, F32.neg({5.0 : F32}), {5.0 : F32})

# Reprodução: o pipeline guloso (mu+1) da Evolução Diferencial montado por
# combinadores — `Op.cross_vec4_differential` gera o vetor-teste
# (DE/current-to-best com crossover por coordenada) e `Op.pipe_greedy` só o
# aceita se o custo Rastrigin não piorar em relação ao alvo.
def reproduce(target: V.Vec4, champ: V.Vec4, seed: U32) -> V.Vec4:
  Op.pipe_greedy(~V.Vec4, ~eval_rastrigin, ~Op.cross_vec4_differential, target, champ, seed)

def main_seed() -> U32:
  31415926

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 64 vetores contínuos em R^4 na árvore de população
  +pop0 = GA.gen_population(~V.Vec4, ~gen_rand_vec, ~fitness, 6n, s0)
  +best0 = GA.best_ind(V.Vec4, pop0)
  +v0 = GA.Ind.gene(V.Vec4, best0)
  +c0 = eval_rastrigin(v0)

  # Executar 80 gerações de Evolução Diferencial com motor genérico
  +pop_fin = GA.run_generations(~V.Vec4, ~reproduce, ~fitness, 80n, pop0, 12345)
  +best_fin = GA.best_ind(V.Vec4, pop_fin)
  +v_fin = GA.Ind.gene(V.Vec4, best_fin)
  +c_fin = eval_rastrigin(v_fin)

  IO.print(
    "=== CENÁRIO 14: EVOLUÇÃO DIFERENCIAL CONTÍNUA (DE / RASTRIGIN 4D) ===\n" ++
    "Espaço de Busca: R^4 em [-5.0, 5.0]^4 (Otimização Numérica com F32)\n" ++
    "Função Objetivo: Benchmark Rastrigin 4D (Multi-Modal com Dezenas de Mínimos Locais)\n" ++
    "Mínimo Global Teórico: 0.0 na origem (0.0, 0.0, 0.0, 0.0)\n" ++
    "População: 64 vetores contínuos (Árvore Binária Profundidade 6)\n" ++
    "Módulos da Lib Utilizados: utils/vec4.bend, operators.bend (Seção D) e motor ga.bend\n\n" ++
    "Geração 0  - Custo Mínimo: " ++ F32.show(c0) ++ " | Vetor: " ++ V.Vec4.show(v0) ++ "\n" ++
    "Geração 80 - Custo Mínimo: " ++ F32.show(c_fin) ++ " | Vetor: " ++ V.Vec4.show(v_fin) ++ "\n\n" ++
    "Convergência Bem-Sucedida (Custo < 2.0 em Paisagem Multi-Modal)? " ++
    Bool.show(F32.is_lt(c_fin, 2.0)) ++ "\n"
  )
