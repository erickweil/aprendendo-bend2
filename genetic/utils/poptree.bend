import Base

# Árvore Populacional Binária Polimórfica (Data Kind)
type PopTree<-A: Data> is Data:
  Leaf{val: A}
  Node{left: PopTree<A>, right: PopTree<A>}

def leaf(-A: Data, +val: A) -> PopTree<A>:
  Leaf{val}

def node(-A: Data, left: PopTree<A>, right: PopTree<A>) -> PopTree<A>:
  Node{left, right}

# Injeta campeão / elite na folha mais à esquerda
def inject_elite(-A: Data, tree: PopTree<A>, +elite: A) -> PopTree<A>:
  match tree:
    case Leaf{_}:
      Leaf{elite}
    case Node{left, right}:
      Node{inject_elite(A, left, elite), right}

# Tamanho estrutural da árvore (contagem exata de indivíduos em Nat)
def tree_size(-A: Data, t: PopTree<A>) -> Nat:
  match t:
    case Leaf{_}:
      1n
    case Node{left, right}:
      Nat.add(tree_size(A, left), tree_size(A, right))

# Geração de árvore uniforme balanceada de profundidade d
def gen_uniform(-A: Data, d: Nat, +val: A) -> PopTree<A>:
  match d:
    case 0n:
      Leaf{val}
    case 1n++p:
      Node{gen_uniform(A, p, val), gen_uniform(A, p, val)}

# Potência de 2 estrutural em Nat
def pow2(d: Nat) -> Nat:
  match d:
    case 0n:
      1n
    case 1n++p:
      Nat.add(pow2(p), pow2(p))

# Profundidade da árvore (altura balanceada à esquerda)
def tree_depth(-A: Data, t: PopTree<A>) -> Nat:
  match t:
    case Leaf{_}:
      0n
    case Node{left, _}:
      1n + tree_depth(A, left)

# Inversão estrutural de árvore (espelhamento)
def tree_reverse(-A: Data, t: PopTree<A>) -> PopTree<A>:
  match t:
    case Leaf{val}:
      Leaf{val}
    case Node{left, right}:
      Node{tree_reverse(A, right), tree_reverse(A, left)}


