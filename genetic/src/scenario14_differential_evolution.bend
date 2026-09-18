import Base
import ./../utils/random.bend as R
import ./../utils/poptree.bend as T

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

type DEInd is Data:
  DEInd{gene: Vec4, cost: F32}

def make_de_ind(+gene: Vec4) -> DEInd:
  DEInd{gene, eval_rastrigin(gene)}

def DEInd.gene(i: DEInd) -> Vec4:
  DEInd{g, _} = i
  g

def DEInd.cost(i: DEInd) -> F32:
  DEInd{_, c} = i
  c

# Seleciona o indivíduo de menor custo (minimização contínua)
def pick_better_de(+a: DEInd, +b: DEInd) -> DEInd:
  Bool.pick(DEInd, F32.is_le(DEInd.cost(a), DEInd.cost(b)), a, b)

def best_de_pop(tree: T.PopTree<DEInd>) -> DEInd:
  match tree:
    case T.Leaf{ind}:
      ind
    case T.Node{left, right}:
      bl br = best_de_pop(left) best_de_pop(right)
      pick_better_de(bl, br)

# Amostra um float em [-5.0, 5.0] a partir de uma semente U32
def rnd_coord(+seed: U32) -> F32:
  +val = U32.to_f32(U32.mod(seed, 10000))
  +norm = (val / 10000.0 : F32)
  ((norm * 10.0) - 5.0 : F32)

def gen_rand_vec(+seed: U32) -> Vec4:
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2)
  make_vec4(rnd_coord(s0), rnd_coord(s1), rnd_coord(s2), rnd_coord(s3))

def gen_de_pop(d: Nat, +seed: U32) -> T.PopTree<DEInd>:
  match d:
    case 0n:
      T.leaf(DEInd, make_de_ind(gen_rand_vec(seed)))
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_de_pop(p, R.split.fst(seed)) gen_de_pop(p, R.split.snd(seed))
      T.node(DEInd, l, r)

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

# Reprodução da População Diferencial em Árvore Paralela
def reproduce_de(tree: T.PopTree<DEInd>, +seed: U32, +champ: DEInd) -> T.PopTree<DEInd>:
  match tree:
    case T.Leaf{+ind}:
      +s1 = R.step(seed)
      +t_vec = DEInd.gene(ind)
      +c_vec = DEInd.gene(champ)
      +trial_vec = mutate_and_cross(t_vec, c_vec, s1)
      +trial_ind = make_de_ind(trial_vec)
      # Seleção gulosa de DE: mantém o filho se o custo for menor ou igual
      T.leaf(DEInd, pick_better_de(trial_ind, ind))
    case T.Node{left, right}:
      +seed = seed
      +champ = champ
      l r = reproduce_de(left, R.split.fst(seed), champ) reproduce_de(right, R.split.snd(seed), champ)
      T.node(DEInd, l, r)

def step_gen(+tree: T.PopTree<DEInd>, +seed: U32) -> T.PopTree<DEInd>:
  +champ = best_de_pop(tree)
  reproduce_de(tree, seed, champ)

def run_de(g: Nat, tree: T.PopTree<DEInd>, +seed: U32) -> T.PopTree<DEInd>:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = R.step(seed)
      +next_tree = step_gen(tree, seed)
      run_de(p, next_tree, next_seed)

def Vec4.show(v: Vec4) -> String:
  Vec4{x0, x1, x2, x3} = v
  "(" ++ F32.show(x0) ++ ", " ++ F32.show(x1) ++ ", " ++ F32.show(x2) ++ ", " ++ F32.show(x3) ++ ")"

def main_seed() -> U32:
  31415926

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 64 vetores contínuos em R^4 na árvore de população
  +pop0 = gen_de_pop(6n, s0)
  +best0 = best_de_pop(pop0)
  +c0 = DEInd.cost(best0)
  +v0 = DEInd.gene(best0)

  # Executar 80 gerações de Evolução Diferencial
  +pop_fin = run_de(80n, pop0, 12345)
  +best_fin = best_de_pop(pop_fin)
  +c_fin = DEInd.cost(best_fin)
  +v_fin = DEInd.gene(best_fin)

  IO.print(
    "=== CENÁRIO 14: EVOLUÇÃO DIFERENCIAL CONTÍNUA (DE / RASTRIGIN 4D) ===\n" ++
    "Espaço de Busca: R^4 em [-5.0, 5.0]^4 (Otimização Numérica com F32)\n" ++
    "Função Objetivo: Benchmark Rastrigin 4D (Multi-Modal com Dezenas de Mínimos Locais)\n" ++
    "Mínimo Global Teórico: 0.0 na origem (0.0, 0.0, 0.0, 0.0)\n" ++
    "População: 64 vetores contínuos (Árvore Binária Profundidade 6)\n" ++
    "Módulos da Lib Utilizados: genetic/utils/random.bend e genetic/utils/poptree.bend\n\n" ++
    "Geração 0  - Custo Mínimo: " ++ F32.show(c0) ++ " | Vetor: " ++ Vec4.show(v0) ++ "\n" ++
    "Geração 80 - Custo Mínimo: " ++ F32.show(c_fin) ++ " | Vetor: " ++ Vec4.show(v_fin) ++ "\n\n" ++
    "Convergência Bem-Sucedida (Custo < 2.0 em Paisagem Multi-Modal)? " ++
    Bool.show(F32.is_lt(c_fin, 2.0)) ++ "\n"
  )
