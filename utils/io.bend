import Base

def pop_or(a, -A: Kind(a), lst: List<a, A>, default: A) -> A:
  match lst:
    case Nil{}: 
      default
    case Con{head, _}: 
      head
