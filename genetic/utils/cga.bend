import Base
import ./random.bend as R

# ================================================================
# BEND 2 GENETIC UTILS - CELLULAR GENETIC ALGORITHM (cga.bend)
# ================================================================
# Motor genérico de Algoritmo Genético Celular (cGA) em grade espacial
# 2D representada como QuadTree balanceada paralela.
# Preserva localidade espacial em 4 quadrantes com difusão de bordas.
# ================================================================

type QuadTree<-A: Data> is Data:
  QLeaf{cell: A}
  QNode{tl: QuadTree<A>, tr: QuadTree<A>, bl: QuadTree<A>, br: QuadTree<A>}

# Geração paralela de malha espacial 2D de profundidade d (tamanho = 4^d células)
def gen_quad(~A: Type, ~init: U32 -> A, d: Nat, +seed: U32) -> QuadTree<A>:
  match d:
    case 0n:
      QLeaf{init(seed)}
    case 1n+p:
      +p = p
      +seed = seed
      +s1 = R.split.fst(seed)
      +s2 = R.split.snd(seed)
      +s3 = R.split.trd(seed)
      +s4 = R.split.fth(seed)
      q1 q2 = gen_quad(~A, ~init, p, s1) gen_quad(~A, ~init, p, s2)
      q3 q4 = gen_quad(~A, ~init, p, s3) gen_quad(~A, ~init, p, s4)
      QNode{q1, q2, q3, q4}

# Extração do melhor indivíduo na malha celular usando comparador genérico
def quad_best(~A: Type, ~better: A -> A -> A, q: QuadTree<A>) -> A:
  match q:
    case QLeaf{cell}:
      cell
    case QNode{tl, tr, bl, br}:
      +b1 = quad_best(~A, ~better, tl)
      +b2 = quad_best(~A, ~better, tr)
      +b3 = quad_best(~A, ~better, bl)
      +b4 = quad_best(~A, ~better, br)
      better(better(b1, b2), better(b3, b4))

# Avanço geracional concorrente dos 4 quadrantes
def step_quad(~A: Type, ~mate_replace: A -> A -> U32 -> A, q: QuadTree<A>, +seed: U32) -> QuadTree<A>:
  match q:
    case QLeaf{cell}:
      QLeaf{cell}
    case QNode{tl, tr, bl, br}:
      match tl tr bl br:
        case QLeaf{+c_tl} QLeaf{+c_tr} QLeaf{+c_bl} QLeaf{+c_br}:
          +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
          +new_tl = mate_replace(c_tl, c_tr, s1)
          +new_tr = mate_replace(c_tr, c_br, s2)
          +new_br = mate_replace(c_br, c_bl, s3)
          +new_bl = mate_replace(c_bl, c_tl, s4)
          QNode{QLeaf{new_tl}, QLeaf{new_tr}, QLeaf{new_bl}, QLeaf{new_br}}
        case _ _ _ _:
          +seed = seed
          +s1 = R.split.fst(seed)
          +s2 = R.split.snd(seed)
          +s3 = R.split.trd(seed)
          +s4 = R.split.fth(seed)
          ntl ntr = step_quad(~A, ~mate_replace, tl, s1) step_quad(~A, ~mate_replace, tr, s2)
          nbl nbr = step_quad(~A, ~mate_replace, bl, s3) step_quad(~A, ~mate_replace, br, s4)
          QNode{ntl, ntr, nbl, nbr}

# Difusão de bordas entre quadrantes para migração de nichos
def diffuse_borders(-A: Data, q: QuadTree<A>) -> QuadTree<A>:
  match q:
    case QLeaf{cell}:
      QLeaf{cell}
    case QNode{tl, tr, bl, br}:
      QNode{tl, bl, tr, br}

# Executa g gerações do algoritmo genético celular
def run_cga(~A: Type, ~mate_replace: A -> A -> U32 -> A, g: Nat, q: QuadTree<A>, +seed: U32) -> QuadTree<A>:
  match g:
    case 0n:
      q
    case 1n+p:
      +s_step = R.step(seed)
      +stepped = step_quad(~A, ~mate_replace, q, seed)
      +diffused = Bool.pick(QuadTree<A>, U32.is_zero(U32.mod(s_step, 3)), diffuse_borders(A, stepped), stepped)
      run_cga(~A, ~mate_replace, p, diffused, s_step)
