import Base
import ./../utils/random.bend as R
import ./../utils/poptree.bend as T
import ./../utils/math.bend as M

# ================================================================
# CENÁRIO 15: NEUROEVOLUÇÃO E CONTROLE CONTÍNUO (CART-POLE / F32)
# ================================================================
# Arquitetura:
# - Física: Simulação contínua do Pêndulo Invertido (Cart-Pole Runge-Kutta/Euler)
# - Genótipo: Pesos e Bias da Rede Neural de Controle em F32
# - Seleção e Crossover: Reprodução paralela em Árvore Binária Fork-Join
# - Biblioteca: genetic/utils/math.bend, random.bend e poptree.bend
# ================================================================

# Rede Neural / Política Linear-Sigmoidal de Controle
type Policy is Data:
  Policy{w0: F32, w1: F32, w2: F32, w3: F32, b: F32}

def make_policy(+w0: F32, +w1: F32, +w2: F32, +w3: F32, +b: F32) -> Policy:
  Policy{w0, w1, w2, w3, b}

# Estado Físico do Sistema Cart-Pole
# x: posição do carrinho (m)
# x_dot: velocidade do carrinho (m/s)
# theta: ângulo da haste em relação à vertical (radianos)
# theta_dot: velocidade angular da haste (rad/s)
type CartPole is Data:
  CartPole{x: F32, x_dot: F32, theta: F32, theta_dot: F32}

def make_cartpole(+x: F32, +x_dot: F32, +theta: F32, +theta_dot: F32) -> CartPole:
  CartPole{x, x_dot, theta, theta_dot}

type SimState is Data:
  Alive{cp: CartPole}
  Dead{}

# Passo de Integração da Dinâmica Física Não-Linear
def step_cartpole(state: CartPole, +force: F32) -> CartPole:
  CartPole{x, x_dot, theta, theta_dot} = state
  +x = x
  +x_dot = x_dot
  +theta = theta
  +theta_dot = theta_dot

  +gravity = {9.8 : F32}
  +masscart = {1.0 : F32}
  +total_mass = {1.1 : F32}
  +length = {0.5 : F32}
  +polemass_length = {0.05 : F32}
  +dt = {0.02 : F32}

  +costheta = F32.cos(theta)
  +sintheta = F32.sin(theta)

  +temp = ((force + (polemass_length * theta_dot * theta_dot * sintheta)) / total_mass : F32)
  +thetaacc_num = ((gravity * sintheta) - (costheta * temp) : F32)
  +thetaacc_den = (length * ({1.33333333 : F32} - ((polemass_length * costheta * costheta) / total_mass)) : F32)
  +thetaacc = (thetaacc_num / thetaacc_den : F32)
  +xacc = (temp - ((polemass_length * thetaacc * costheta) / total_mass) : F32)

  +new_x = (x + (dt * x_dot) : F32)
  +new_x_dot = (x_dot + (dt * xacc) : F32)
  +new_theta = (theta + (dt * theta_dot) : F32)
  +new_theta_dot = (theta_dot + (dt * thetaacc) : F32)
  CartPole{new_x, new_x_dot, new_theta, new_theta_dot}

# Decisão da Rede Neural: ativação softsign contínua escalada para [-10N, +10N]
def decide_force(+state: CartPole, +pol: Policy) -> F32:
  CartPole{x, x_dot, theta, theta_dot} = state
  Policy{w0, w1, w2, w3, b} = pol
  +act_input = (M.dot4(x, x_dot, theta, theta_dot, w0, w1, w2, w3) + b : F32)
  (M.fast_tanh(act_input) * {10.0 : F32} : F32)

# Atualização de estado da simulação com verificação de falha física (|x| > 2.4 ou |theta| > 12 graus)
def step_sim(+st: SimState, +pol: Policy) -> SimState:
  match st:
    case Dead{}:
      Dead{}
    case Alive{CartPole{+x, +x_dot, +theta, +theta_dot}}:
      +x_fail = F32.is_gt(F32.abs(x), {2.4 : F32})
      +th_fail = F32.is_gt(F32.abs(theta), {0.20944 : F32})
      +failed = Bool.or(x_fail, th_fail)
      +cp = make_cartpole(x, x_dot, theta, theta_dot)
      Bool.pick(SimState, failed,
        Dead{},
        Alive{step_cartpole(cp, decide_force(cp, pol))})

# Loop de simulação delimitado por Nat fuel
def sim_loop(steps: Nat, +st: SimState, +pol: Policy, +accum: U32) -> U32:
  match steps:
    case 0n:
      accum
    case 1n+p:
      match st:
        case Dead{}:
          accum
        case Alive{_}:
          +next_st = step_sim(st, pol)
          sim_loop(p, next_st, pol, U32.inc(accum))

# Avaliação de Aptidão: soma de sobrevivência para perturbação positiva e negativa (Máximo = 200 passos)
def eval_policy(+pol: Policy) -> U32:
  +init_pos = {Alive{make_cartpole({0.0 : F32}, {0.0 : F32}, {0.05 : F32}, {0.0 : F32})} : SimState}
  +init_neg = {Alive{make_cartpole({0.0 : F32}, {0.0 : F32}, F32.neg({0.05 : F32}), {0.0 : F32})} : SimState}
  +fit_pos = sim_loop(100n, init_pos, pol, 0)
  +fit_neg = sim_loop(100n, init_neg, pol, 0)
  (fit_pos + fit_neg : U32)

# Indivíduo da População de Neuroevolução
type NeuroInd is Data:
  NeuroInd{pol: Policy, fit: U32}

def make_neuro_ind(+pol: Policy) -> NeuroInd:
  NeuroInd{pol, eval_policy(pol)}

def NeuroInd.pol(i: NeuroInd) -> Policy:
  NeuroInd{p, _} = i
  p

def NeuroInd.fit(i: NeuroInd) -> U32:
  NeuroInd{_, f} = i
  f

def pick_better_neuro(+a: NeuroInd, +b: NeuroInd) -> NeuroInd:
  Bool.pick(NeuroInd, U32.is_ge(NeuroInd.fit(a), NeuroInd.fit(b)), a, b)

def best_neuro_pop(tree: T.PopTree<NeuroInd>) -> NeuroInd:
  match tree:
    case T.Leaf{ind}:
      ind
    case T.Node{left, right}:
      bl br = best_neuro_pop(left) best_neuro_pop(right)
      pick_better_neuro(bl, br)

# Geração de peso aleatório em [-2.0, 2.0]
def rnd_weight(+seed: U32) -> F32:
  +val = U32.to_f32(U32.mod(seed, 4000))
  +norm = (val / {1000.0 : F32} : F32)
  (norm - {2.0 : F32} : F32)

def gen_rand_policy(+seed: U32) -> Policy:
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  make_policy(rnd_weight(s0), rnd_weight(s1), rnd_weight(s2), rnd_weight(s3), rnd_weight(s4))

def gen_neuro_pop(d: Nat, +seed: U32) -> T.PopTree<NeuroInd>:
  match d:
    case 0n:
      T.leaf(NeuroInd, make_neuro_ind(gen_rand_policy(seed)))
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_neuro_pop(p, R.split.fst(seed)) gen_neuro_pop(p, R.split.snd(seed))
      T.node(NeuroInd, l, r)

# Operadores Genéticos em F32: Mutação com jitter contínuo e Crossover
def mutate_weight(+w: F32, +seed: U32) -> F32:
  +should_mut = R.chance(seed, 40)
  +jitter = rnd_weight(R.step(seed))
  Bool.pick(F32, should_mut, (w + (jitter * {0.5 : F32}) : F32), w)

def cross_weight(+w1: F32, +w2: F32, +rnd: U32) -> F32:
  Bool.pick(F32, R.chance(rnd, 50), w1, w2)

def reproduce_policy(+parent: Policy, +champ: Policy, +seed: U32) -> Policy:
  Policy{pw0, pw1, pw2, pw3, pb} = parent
  Policy{cw0, cw1, cw2, cw3, cb} = champ
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +r0 = R.step(s4);   +r1 = R.step(r0); +r2 = R.step(r1); +r3 = R.step(r2); +r4 = R.step(r3)
  make_policy(
    mutate_weight(cross_weight(pw0, cw0, r0), s0),
    mutate_weight(cross_weight(pw1, cw1, r1), s1),
    mutate_weight(cross_weight(pw2, cw2, r2), s2),
    mutate_weight(cross_weight(pw3, cw3, r3), s3),
    mutate_weight(cross_weight(pb, cb, r4), s4)
  )

def reproduce_neuro(tree: T.PopTree<NeuroInd>, +seed: U32, +champ: NeuroInd) -> T.PopTree<NeuroInd>:
  match tree:
    case T.Leaf{+ind}:
      +s1 = R.step(seed)
      +child_pol = reproduce_policy(NeuroInd.pol(ind), NeuroInd.pol(champ), s1)
      +child_ind = make_neuro_ind(child_pol)
      T.leaf(NeuroInd, pick_better_neuro(child_ind, ind))
    case T.Node{left, right}:
      +seed = seed
      +champ = champ
      l r = reproduce_neuro(left, R.split.fst(seed), champ) reproduce_neuro(right, R.split.snd(seed), champ)
      T.node(NeuroInd, l, r)

def step_neuro_gen(+tree: T.PopTree<NeuroInd>, +seed: U32) -> T.PopTree<NeuroInd>:
  +champ = best_neuro_pop(tree)
  reproduce_neuro(tree, seed, champ)

def run_neuro(g: Nat, tree: T.PopTree<NeuroInd>, +seed: U32) -> T.PopTree<NeuroInd>:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = R.step(seed)
      +next_tree = step_neuro_gen(tree, seed)
      run_neuro(p, next_tree, next_seed)

def Policy.show(p: Policy) -> String:
  Policy{w0, w1, w2, w3, b} = p
  "[x:" ++ F32.show(w0) ++ ", x':" ++ F32.show(w1) ++ ", th:" ++ F32.show(w2) ++ ", th':" ++ F32.show(w3) ++ ", b:" ++ F32.show(b) ++ "]"

def main_seed() -> U32:
  987654321

def main() -> IO(Unit):
  +s0 = main_seed()
  # População inicial: 32 redes neurais em árvore de profundidade 5
  +pop0 = gen_neuro_pop(5n, s0)
  +best0 = best_neuro_pop(pop0)
  +f0 = NeuroInd.fit(best0)
  +p0 = NeuroInd.pol(best0)

  # Evolução por 45 gerações
  +pop_fin = run_neuro(45n, pop0, 13579)
  +best_fin = best_neuro_pop(pop_fin)
  +f_fin = NeuroInd.fit(best_fin)
  +p_fin = NeuroInd.pol(best_fin)

  IO.print(
    "=== CENÁRIO 15: NEUROEVOLUÇÃO E CONTROLE CONTÍNUO (CART-POLE / F32) ===\n" ++
    "Ambiente: Dinâmica Física Não-Linear do Pêndulo Invertido (dt=0.02s, F=±10N)\n" ++
    "Controlador: Rede Neural Contínua F32 com Ativação Softsign / Fast Tanh\n" ++
    "População: 32 redes neurais (Árvore Fork-Join de Profundidade 5)\n" ++
    "Meta de Aptidão: 200/200 passos mantidos em equilíbrio (±0.05 rad iniciais)\n" ++
    "Módulos da Lib Utilizados: genetic/utils/math.bend, random.bend e poptree.bend\n\n" ++
    "Geração 0  - Sobrevivência: " ++ U32.show(f0) ++ "/200 passos | Pesos: " ++ Policy.show(p0) ++ "\n" ++
    "Geração 45 - Sobrevivência: " ++ U32.show(f_fin) ++ "/200 passos | Pesos: " ++ Policy.show(p_fin) ++ "\n\n" ++
    "Controle Equilibrado com Sucesso (>= 180 passos)? " ++
    Bool.show(U32.is_ge(f_fin, 180)) ++ "\n"
  )
