import Base

# Árvore Populacional Binária Polimórfica (Data Kind).
# É a forma da população no motor: fork-join perfeitamente balanceado, com
# 2^d indivíduos nas folhas.
type PopTree<-A: Data> is Data:
  Leaf{val: A}
  Node{left: PopTree<A>, right: PopTree<A>}

# Contagem exata de indivíduos. Existe para as leis: é a medida sobre a qual se
# enuncia que a evolução não cria nem destrói indivíduos.
def tree_size(-A: Data, t: PopTree<A>) -> Nat:
  match t:
    case Leaf{_}:
      1n
    case Node{left, right}:
      Nat.add(tree_size(A, left), tree_size(A, right))
