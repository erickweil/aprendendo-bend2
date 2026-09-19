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

# A FAZER/TODO: pensar melhor esses utilitários de IO

# Primeiro argumento da linha de comando como U32, ou o default se não houver
# argumento ou se ele não for um número. Usado pelos exemplos para receber a
# semente do gerador aleatório.
def arg_u32(args: List<String>, default: U32) -> U32:
  match args:
    case Nil{}:
      default
    case Con{first, rest}:
      unwrap_or(U32, U32.read(first), default)

# Os argumentos da linha de comando chegam como `List<&1, String>`, que é afim
# (só pode ser percorrida uma vez). `numbers` converte tudo de uma vez numa
# lista `Data`, que pode ser consultada quantas vezes for preciso.
def numbers(args: List<String>) -> List<&2, Maybe<&2, U32>>:
  match args:
    case Nil{}:
      Nil{}
    case Con{first, rest}:
      Con{U32.read(first), numbers(rest)}

# O k-ésimo número (a partir de 0), ou o default se faltar ou não for número
def num_at(l: List<&2, Maybe<&2, U32>>, k: Nat, default: U32) -> U32:
  match l k:
    case Nil{} 0n:
      default
    case Nil{} 1n+p:
      default
    case Con{first, rest} 0n:
      unwrap_or(U32, first, default)
    case Con{first, rest} 1n+p:
      num_at(rest, p, default)
