import Base

# Como lidar com um resultado `Array<A> & B`
# -----------------------------------
# O jeito óbvio NÃO compila:
#
#   (a, n) = Array.size(U32, a)   # a match cannot scrutinize a computed value
# 1. Uma função que recebe o par como parâmetro e o desestrutura:
#      def mostra_tamanho(r: Array<U32> & U32) -> String:
#        (a, n) = r
#        U32.show(n)
#
# por isso temos aqui o `with`, que desestrutura o par e entrega as duas metades a uma lambda.
# with(U32, U32, String, Array.size(U32, a), a => n => U32.show(n))
def with(-A: Type, -B: Type, -C: Type, p: Array<A> & B, k: Array<A> -> B -> C) -> C:
  (a, b) = p
  k(a, b)

def for_each.go(~T: Data, ~f: T -> U32 -> T, k: Nat, r: Array<T> & T, +i: U32) -> Array<T>:
  match k:
    case 0n:
      (a, v) = r
      Array.set(T, a, i, f(v, i))
    case 1n+p:
      (a, v) = r
      a = Array.set(T, a, i, f(v, i))
      for_each.go(~T, ~f, p, Array.get(T, a, (i + 1 : U32)), (i + 1 : U32))

# `iter_mut().for_each(|x| *x = f(*x))`
# In-place, escreve no mesmo array. A callback recebe o valor e o índice do elemento, e deve retornar o novo valor
def for_each(~T: Data, ~f: T -> U32 -> T, a: Array<T>) -> Array<T>:
  with(T, U32, Array<T>, Array.size(T, a), a => n => 
    for_each.go(~T, ~f, U32.to_nat((n - 1 : U32)), Array.get(T, a, 0), 0)
  )

def from_fn.go(~T: Type, ~f: U32 -> T, d: Nat, +start: U32, +size: U32) -> Array<T>:
  match d:
    case 0n:
      ALeaf{f(start)}
    case 1n+p:
      +p = p
      +h = U32.shr(size)
      l r = from_fn.go(~T, ~f, p, start, h) from_fn.go(~T, ~f, p, (start + h : U32), h)
      ANode{l, r}

# Equivalente ao for_each mas a ideia é criar um array já com a função (paralelo)
def from_fn(~T: Type, ~f: U32 -> T, +d: Nat) -> Array<T>:
  from_fn.go(~T, ~f, d, 0, U32.shln(1, d))

# `a.iter().zip(b).map(|(x, y)| f(x, y))` (paralelo)
# Consome os dois arrays do mesmo tamanho para gerar um novo array 
# ATENÇÃO: se não tiverem o mesmo tamanho você recebe um array desbalanceado.
def zip_with(~T: Type, ~U: Type, ~V: Type, ~f: T -> U -> V, a: Array<T>, b: Array<U>) -> Array<V>:
  match a b:
    case ALeaf{x} ALeaf{y}:
      ALeaf{f(x, y)}
    case ANode{xs, ys} ANode{zs, ws}:
      l r = zip_with(~T, ~U, ~V, ~f, xs, zs) zip_with(~T, ~U, ~V, ~f, ys, ws)
      ANode{l, r}
    case ALeaf{x} ANode{zs, ws}:
      zip_with(~T, ~U, ~V, ~f, ALeaf{x}, zs)
    case ANode{xs, ys} ALeaf{y}:
      zip_with(~T, ~U, ~V, ~f, xs, ALeaf{y})

# `[a, b].concat()`
# Consome os dois arrays para gerar um array que junta os dois, sem copiar os elementos.
# ATENÇÃO: se não tiverem o mesmo tamanho você recebe um array desbalanceado.
def concat(~T: Type, a: Array<T>, b: Array<T>) -> Array<T>:
  ANode{a, b}

# `a.reverse()` (paralelo)
# Consome o array para gerar um novo array com os elementos na ordem inversa.
def reverse(~T: Type, a: Array<T>) -> Array<T>:
  match a:
    case ALeaf{x}:
      ALeaf{x}
    case ANode{xs, ys}:
      l r = reverse(~T, ys) reverse(~T, xs)
      ANode{l, r}

# Consome o array chamando a função f para cada elemento
def reduce_consume(~A: Type, ~S: Type, ~f: @x: A -> @a: S -> S, arr: Array<A>, acc: S) -> S:
  match arr:
    case ALeaf{x}:
      f(acc, x)
    case ANode{xs, ys}:
      # Primeiro esquerda
      acc = reduce_consume(~A, ~S, ~f, xs, acc)
      # Depois direita
      reduce_consume(~A, ~S, ~f, ys, acc)

# Versão do reduce que duplica os valores para não consumir o array original
def reduce(~A: Data, ~S: Type, ~f: @+x: A -> @a: S -> S, arr: Array<A>, acc: S) -> Array<A> & S:
  match arr:
    case ALeaf{+x}:
      (ALeaf{x}, f(acc, x))
    case ANode{xs, ys}:
      # Primeiro esquerda
      xs_acc = reduce(~A, ~S, ~f, xs, acc)
      with(A, S, Array<A> & S, xs_acc, xs => acc =>
        # Depois direita
        ys_acc = reduce(~A, ~S, ~f, ys, acc)
        with(A, S, Array<A> & S, ys_acc, ys => acc =>
          (ANode{xs, ys}, acc)
        )
      )

def show.go(~T: Type, ~fn: T -> String, arr: Array<T>) -> String:
  match arr:
    case ALeaf{x}:
      fn(x)
    case ANode{xs, ys}:
      show.go(~T, ~fn, xs) ++ ", " ++ show.go(~T, ~fn, ys)

def show(~T: Type, ~fn: T -> String, arr: Array<T>) -> String:
  "[" ++ show.go(~T, ~fn, arr) ++ "]"