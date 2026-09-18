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
