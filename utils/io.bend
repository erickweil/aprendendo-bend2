import Base

def pop_or(a, -A: Kind(a), lst: List<a, A>, default: A) -> A:
  match lst:
    case Nil{}: 
      default
    case Con{head, _}: 
      head

def unwrap_or(-A: Data, m: Maybe<&2, A>, default: A) -> A:
  match m:
    case None{}:
      default
    case Some{val}:
      val

# Primeiro argumento da linha de comando como U32, ou o default se não houver
# argumento ou se ele não for um número. Usado pelos exemplos para receber a
# semente do gerador aleatório.
def arg_u32(args: List<String>, default: U32) -> U32:
  match args:
    case Nil{}:
      default
    case Con{first, rest}:
      unwrap_or(U32, U32.read(first), default)
