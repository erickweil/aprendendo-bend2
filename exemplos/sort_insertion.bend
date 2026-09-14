import Base

def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

# Carrega o elemento inicial para a posição correta na lista ordenada.
def insertion_sort.step(+lista: List<&2, U32>) -> List<&2, U32>:
  match lista:
    case Nil{}:
      Nil{}
    case Con{a, Nil{}}:
      Con{a, Nil{}}
    case Con{a, Con{b, tail}}:
      # Se a > b, troca a e b, senão mantém a ordem
      pick(List<&2, U32>, (a > b : U32),
        Con{b, insertion_sort.step(Con{a, tail})},
        Con{a, Con{b, tail}}
      )

# Insertion sort funcional
def insertion_sort(lista: List<&2, U32>) -> List<&2, U32>:
  match lista:
    case Nil{}:
      Nil{}
    case Con{head, tail}:
      resto = insertion_sort(tail)
      insertion_sort.step(Con{head, resto})


def mostrar(lista: List<&2, U32>) -> String:
  match lista:
    case Nil{}:
      ""
    case Con{h, t}:
      U32.show(h) ++ ", " ++ mostrar(t)

def valores() -> List<&2, U32>:
  [5, 3, 8, 1, 4, 7, 2, 6, 9, 0, 4, 3] 

def main() -> IO(Unit):
  +lista = valores()
  IO.print(
    "Lista original: " ++ mostrar(lista) ++ "\n" ++
    "Lista ordenada: " ++ mostrar(insertion_sort(lista))
  )