import Base

def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

# Em Bend2 toda função de dois parâmetros def f(a, b) é na verdade a => b => (...)
# A função f recebe um elemento da lista e o acumulado e deve retornar novamente o acumulado
def reduce(~A: Data, ~S: Data, ~f: @+a: S -> @+x: A -> S, xs: List<&2, A>, acc: S) -> S:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      reduce(~A, ~S, ~f, t, f(acc, h))

# map_or do Option do Rust
def Maybe.map_or(-A: Data, -B: Data, maybe: Maybe<&2, A>, f: A -> B, default: B) -> B:
  match maybe:
    case None{}:
      default
    case Some{valor}:
      f(valor)

def mostrar(lista: List<&2, U32>) -> String:
  reduce(~U32, ~String, ~(acc => x => acc ++ U32.show(x) ++ ", "), lista, "")

type Arvore<-T: Data> is Data:
  Vazia{}
  No{valor: T, esquerda: Arvore<T>, direita: Arvore<T>}

def Arvore.inserir(~T: Data, ~cmp: @a: T -> @b: T -> Cmp, +a: Arvore<T>, +novo: T) -> Arvore<T>:
  match a:
    case Vazia{}:
      No{novo, Vazia{}, Vazia{}}
    case No{valor, esquerda, direita}:
      pick(Arvore<T>, Cmp.is_lt(cmp(novo, valor)),
        No{valor, Arvore.inserir(~T, ~cmp, esquerda, novo), direita},
        No{valor, esquerda, Arvore.inserir(~T, ~cmp, direita, novo)}
      )

def Arvore.buscar(~T: Data, ~cmp: @a: T -> @b: T -> Cmp, +a: Arvore<T>, +busca: T) -> Maybe<&2, T>:
  match a:
    case Vazia{}:
      None{}
    case No{valor, esquerda, direita}:
      pick(Maybe<&2, T>, Cmp.is_eq(cmp(busca, valor)),
        Some{valor},
        pick(Maybe<&2, T>, Cmp.is_lt(cmp(busca, valor)),
          Arvore.buscar(~T, ~cmp, esquerda, busca),
          Arvore.buscar(~T, ~cmp, direita, busca)
        )
      )
  
def Arvore.travessia(~T: Data, ~S: Data, ~f: @+a: S -> @+x: T -> S, arvore: Arvore<T>, acc: S) -> S:
  match arvore:
    case Vazia{}:
      acc
    case No{valor, esquerda, direita}:
      acc1 = Arvore.travessia(~T, ~S, ~f, esquerda, acc)
      acc2 = f(acc1, valor)
      Arvore.travessia(~T, ~S, ~f, direita, acc2)

def valores() -> List<&2, U32>:
  [5, 777, 8, 1, 4, 7, 2, 6, 9, 666, 3]

def main() -> IO(Unit):
  +arvore = reduce(~U32, ~Arvore<U32>, ~(acc => x => Arvore.inserir(~U32, ~U32.cmp, acc, x)), valores(), Vazia{})

  +ordenados = Arvore.travessia(~U32, ~String, ~(acc => x => acc ++ U32.show(x) ++ " "), arvore, "")
  contem = Arvore.buscar(~U32, ~U32.cmp, arvore, 0)
  IO.print(
    "Árvore contém 0? " ++ Maybe.map_or(U32, String, contem, num => U32.show(num), "Não encontrado") ++ "\n" ++
    "Valores em ordem na árvore: " ++ ordenados ++ "\n"
  )
