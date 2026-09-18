import Base
import ./random.bend as R
import ./poptree.bend as T

# ================================================================
# BEND 2 GENETIC UTILS - MULTI-OBJECTIVE EA (moea.bend)
# ================================================================
# Motor genérico de Algoritmo Evolutivo Multi-Objetivo (MOEA).
# Suporta fronteira de Pareto com co-adaptação em sub-árvores
# e seleção baseada em múltiplos objetivos conflitantes.
# ================================================================

# Geração de árvore populacional genérica
def gen_pop(~A: Type, ~init: U32 -> A, d: Nat, +seed: U32) -> T.PopTree<A>:
  match d:
    case 0n:
      T.Leaf{init(seed)}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(~A, ~init, p, R.split.fst(seed)) gen_pop(~A, ~init, p, R.split.snd(seed))
      T.Node{l, r}

# Redução da árvore com comparador arbitrário (ex: melhor valor, menor custo)
def best_by(~A: Type, ~better: A -> A -> A, tree: T.PopTree<A>) -> A:
  match tree:
    case T.Leaf{ind}:
      ind
    case T.Node{left, right}:
      +bl = best_by(~A, ~better, left)
      +br = best_by(~A, ~better, right)
      better(bl, br)

# Reprodução MOEA paralela na árvore binária:
# Sub-árvores trocam especialistas Pareto com sub-árvores irmãs
def reproduce_mo(~A: Type, ~mate: A -> A -> U32 -> A, ~rank: A -> A -> A,
                 tree: T.PopTree<A>, +seed: U32, +partner: A) -> T.PopTree<A>:
  match tree:
    case T.Leaf{ind}:
      +child = mate(ind, partner, seed)
      T.Leaf{child}
    case T.Node{left, right}:
      +left = left
      +right = right
      +seed = seed
      +partner = partner
      +bl = best_by(~A, ~rank, left)
      +br = best_by(~A, ~rank, right)
      l r = reproduce_mo(~A, ~mate, ~rank, left, R.split.fst(seed), br) reproduce_mo(~A, ~mate, ~rank, right, R.split.snd(seed), bl)
      T.Node{l, r}

def step_moea(~A: Type, ~mate: A -> A -> U32 -> A, ~rank: A -> A -> A,
              +tree: T.PopTree<A>, +seed: U32) -> T.PopTree<A>:
  +champ = best_by(~A, ~rank, tree)
  reproduce_mo(~A, ~mate, ~rank, tree, seed, champ)

def run_moea(~A: Type, ~mate: A -> A -> U32 -> A, ~rank: A -> A -> A,
             g: Nat, tree: T.PopTree<A>, +seed: U32) -> T.PopTree<A>:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = R.step(seed)
      +next_tree = step_moea(~A, ~mate, ~rank, tree, seed)
      run_moea(~A, ~mate, ~rank, p, next_tree, next_seed)
