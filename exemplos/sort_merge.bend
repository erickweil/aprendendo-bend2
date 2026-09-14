import Base

def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

def tamanho(lista: List<&2, U32>) -> U32:
  match lista:
    case Nil{}:
      0
    case Con{head, tail}:
      (tamanho(tail) + 1 : U32)

type Metades is Data:
  Metades{a: List<&2, U32>, b: List<&2, U32>}

def metade.a(metades: Metades) -> List<&2, U32>:
  Metades{a, b} = metades
  a

def metade.b(metades: Metades) -> List<&2, U32>:
  Metades{a, b} = metades
  b

# Irá dividir uma lista em duas metades, onde a metade.a irá ficar com k elementos e a metade.b irá ficar com o restante da lista
def dividir.go(k: Nat, lista: List<&2, U32>) -> Metades:
  match k:
    case 0n:
      Metades{Nil{}, lista}
    case 1n+p:
      match lista:
        case Nil{}:
          Metades{Nil{}, Nil{}}
        case Con{h, t}:
          +resto = dividir.go(p, t)
          Metades{Con{h, metade.a(resto)}, metade.b(resto)}

# def dividir(+lista: List<&2, U32>) -> Metades:
#   dividir.go(U32.to_nat((tamanho(lista) / 2 : U32)), lista)

# Recebe duas metades em ordem e retorna-as unidas em ordem
# n deve ser o tamanho da lista original, que é a soma do tamanho das duas metades
def merge(n: Nat, +metades: Metades) -> List<&2, U32>:
  match n:
    # Chegou no final da lista, então não deveria haver mais elementos a serem unidos
    case 0n:
      Nil{}
    case 1n+p:
      match metades:
        case Metades{Nil{}, Nil{}}:
          Nil{}
        case Metades{Nil{}, Con{h, t}}:
          Con{h, t}
        case Metades{Con{h, t}, Nil{}}:
          Con{h, t}
        case Metades{Con{ha, ta}, Con{hb, tb}}:
          # resto agora está em ordem e ha > ta e hb > tb, mas não sabemos a relação entre ha e tb ou hb e ta
          # ha, ta[3, 5, ...]   hb, tb[14, 16, ...]
          # Pega o menor entre ha e hb e chama merge com o resto da lista que sobrou
          +menor = pick(U32, (ha < hb : U32), ha, hb)
          +resto = pick(Metades, (ha < hb : U32), Metades{ta, Con{hb, tb}}, Metades{Con{ha, ta}, tb})
          Con{menor, merge(p, resto)}

def merge_sort.go(+n: Nat, lista: List<&2, U32>, +len: U32) -> List<&2, U32>:
  match n:
    # Inalcançável
    case 0n:
      Nil{}
    case 1n+p:
      match lista:
        case Nil{}:
          Nil{}
        case Con{h, Nil{}}:
          Con{h, Nil{}}
        case Con{h, Con{h2, t}}:
          +len2 = (len / 2 : U32)
          +metades = dividir.go(U32.to_nat(len2), Con{h, Con{h2, t}})
          # Execução paralela das duas metades
          a b = 
            merge_sort.go(p, metade.a(metades), len2)
            merge_sort.go(p, metade.b(metades), (len - len2 : U32))

          merge(U32.to_nat(len), Metades{a, b})

def merge_sort(+lista: List<&2, U32>) -> List<&2, U32>:
  +len = tamanho(lista)
  merge_sort.go(U32.to_nat(len), lista, len)

def mostrar(lista: List<&2, U32>) -> String:
  match lista:
    case Nil{}:
      ""
    case Con{h, t}:
      U32.show(h) ++ ", " ++ mostrar(t)

def valores() -> List<&2, U32>:
  [5, 777, 8, 1, 4, 7, 2, 6, 9, 666, 3]

def main() -> IO(Unit):
  +lista = valores()
  ordenada = merge_sort(lista)
  IO.print(
    "Lista original: " ++ mostrar(lista) ++ "\n" ++
    "Lista em ordem: " ++ mostrar(ordenada) ++ "\n" ++
    ""
  )
