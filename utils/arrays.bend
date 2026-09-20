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

def for_each.go(~T: Data, ~C: Data, ~f: T -> @+a: C -> U32 -> T, k: Nat, arr: Array<T> & T, +ctx: C, +i: U32) -> Array<T>:
  match k:
    case 0n:
      (arr, v) = arr
      Array.set(T, arr, i, f(v, ctx, i))
    case 1n+p:
      (arr, v) = arr
      arr = Array.set(T, arr, i, f(v, ctx, i))
      +i_next = (i + 1 : U32)
      for_each.go(~T, ~C, ~f, p, Array.get(T, arr, i_next), ctx, i_next)

def for_each(~T: Data, ~C: Data, ~f: T -> @+a: C -> U32 -> T, a: Array<T>, ctx: C) -> Array<T>:
  with(T, U32, Array<T>, Array.size(T, a), a => n => 
    for_each.go(~T, ~C, ~f, U32.to_nat((n - 1 : U32)), Array.get(T, a, 0), ctx, 0)
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

def zip_with.go(~A: Data, ~B: Data, ~f: A -> B -> U32 -> A, k: Nat, a: Array<A> & A, b: Array<B> & B, +i: U32) -> Array<A>:
  match k:
    case 0n:
      (arr_a, value_a) = a
      (arr_b, value_b) = b
      Array.set(A, arr_a, i, f(value_a, value_b, i))
      arr_a
    case 1n+p:
      (arr_a, value_a) = a
      (arr_b, value_b) = b
      arr_a = Array.set(A, arr_a, i, f(value_a, value_b, i))
      +i_next = (i + 1 : U32)
      zip_with.go(~A, ~B, ~f, p, Array.get(A, arr_a, i_next), Array.get(B, arr_b, i_next), i_next)

# `a.iter().zip(b).map(|(x, y)| f(x, y))`
# Consome dois arrays do mesmo tamanho e retorna o primeiro, chamando a função f para cada par de elementos.
# Se um for menor, irá atravessar o menor e ignorar o resto do maior.
def zip_with(~A: Data, ~B: Data, ~f: A -> B -> U32 -> A, a: Array<A>, b: Array<B>) -> Array<A>:
  with(A, U32, Array<A>, Array.size(A, a), a => +size_a =>
  with(B, U32, Array<A>, Array.size(B, b), b => +size_b =>
    size_min = Bool.pick(U32, (size_a < size_b : U32), size_a, size_b)
    zip_with.go(~A, ~B, ~f, U32.to_nat((size_min - 1 : U32)), Array.get(A, a, 0), Array.get(B, b, 0), 0)
  ))

# ---------------- elemento Data ----------------

def swap_at.put(~T: Data, r: Array<T> & T, +i: U32) -> Array<T>:
  (arr, value_j) = r
  Array.set(T, arr, i, value_j)

def swap_at.step(~T: Data, r: Array<T> & T, +i: U32, +j: U32) -> Array<T>:
  (arr, value_i) = r
  swap_at.put(~T, Array.swap(T, arr, j, value_i), i)

# `a.swap(i, j)` — troca duas posições, O(1). Tolera i == j.
def swap_at(~T: Data, arr: Array<T>, +i: U32, +j: U32) -> Array<T>:
  swap_at.step(~T, Array.get(T, arr, i), i, j)

# ---------------- elemento Type (com buraco) ----------------

def swap_at_hole.c(~T: Type, r: Array<T> & T, +i: U32) -> Array<T> & T:
  (arr, value_j) = r
  Array.swap(T, arr, i, value_j)

def swap_at_hole.b(~T: Type, r: Array<T> & T, +i: U32, +j: U32) -> Array<T> & T:
  (arr, value_i) = r
  swap_at_hole.c(~T, Array.swap(T, arr, j, value_i), i)

def swap_at_hole.if(~T: Type, same: Bool, arr: Array<T>, hole: T, +i: U32, +j: U32) -> Array<T> & T:
  match same:
    case True{}:
      (arr, hole)
    case False{}:
      swap_at_hole.b(~T, Array.swap(T, arr, i, hole), i, j)

# Troca duas posições de um array de elemento `Type`, O(1) (3 swaps).
# Recebe o buraco e o devolve junto com o array: (arr, buraco).
# ATENÇÃO: i e j precisam ser < n (os índices dão a volta, então i=0 e j=n são
# o mesmo slot e passariam pela checagem de i == j, deixando o buraco dentro).
def swap_at_hole(~T: Type, arr: Array<T> & T, +i: U32, +j: U32) -> Array<T> & T:
  (arr, hole) = arr
  swap_at_hole.if(~T, U32.is_eq(i, j), arr, hole, i, j)

# Consome o array chamando a função f para cada elemento (Aparentemente não fica lento, e pode ser T: Type)
def reduce_consume(~A: Type, ~S: Type, ~f: @x: A -> @a: S -> S, arr: Array<A>, acc: S) -> S:
  match arr:
    case ALeaf{x}:
      f(x, acc)
    case ANode{xs, ys}:
      # Primeiro esquerda
      acc = reduce_consume(~A, ~S, ~f, xs, acc)
      # Depois direita
      reduce_consume(~A, ~S, ~f, ys, acc)

def reduce.go(~A: Data, ~S: Type, ~f: @+x: A -> @a: S -> U32 -> S, k: Nat, arr: Array<A> & A, +k_prev: U32, acc: S) -> Array<A> & S:
  match k:
    case 0n:
      (arr, value) = arr
      acc = f(value, acc, k_prev)
      (arr, acc)
    case 1n+p:
      (arr, value) = arr
      acc = f(value, acc, k_prev)
      +k_next = (k_prev + 1 : U32)
      reduce.go(~A, ~S, ~f, p, Array.get(A, arr, k_next), k_next, acc)

# Versão do reduce que utiliza apenas operações rápidas e sem desconstruir o array
def reduce(~A: Data, ~S: Type, ~f: @+x: A -> @a: S -> U32 -> S, arr: Array<A>, acc: S) -> Array<A> & S:
  with(A, U32, Array<A> & S, Array.size(A, arr), arr => size => 
    reduce.go(~A, ~S, ~f, U32.to_nat((size - 1 : U32)), Array.get(A, arr, 0), 0, acc)
  )

# recebe (arr, buraco) e devolve (arr, elemento seguinte) — nada de closure
def for_each_hole.next(~T: Type, r: Array<T> & T, +i_next: U32) -> Array<T> & T:
  (arr, hole) = r
  Array.swap(T, arr, i_next, hole)

def for_each_hole.go(~T: Type, ~C: Data, ~f: T -> @+a: C -> U32 -> T, k: Nat, arr: Array<T> & T, +ctx: C, +i: U32) -> Array<T> & T:
  match k:
    case 0n:
      (arr, value) = arr
      Array.swap(T, arr, i, f(value, ctx, i))          # devolve (arr, buraco)
    case 1n+p:
      (arr, value) = arr
      +i_next = (i + 1 : U32)
      for_each_hole.go(~T, ~C, ~f, p,
        for_each_hole.next(~T, Array.swap(T, arr, i, f(value, ctx, i)), i_next),
      ctx, i_next)

def for_each_hole.start(~T: Type, ~C: Data, ~f: T -> @+a: C -> U32 -> T, r: Array<T> & U32, hole: T, +ctx: C) -> Array<T> & T:
  (arr, +size) = r
  for_each_hole.go(~T, ~C, ~f, U32.to_nat((size - 1 : U32)), Array.swap(T, arr, 0, hole), ctx, 0)

# Atravessa o array T: Type, sem mudar de lugar os valores. (com DOIS swaps por elemento)
def for_each_hole(~T: Type, ~C: Data, ~f: T -> @+a: C -> U32 -> T, arr: Array<T> & T, +ctx: C) -> Array<T> & T:
  (arr, hole) = arr
  for_each_hole.start(~T, ~C, ~f, Array.size(T, arr), hole, ctx)

# Atravessa array T: Type, mais rápido que for_each_hole. (com UM swap por elemento)
# O PREÇO: o array termina ROTACIONADO uma posição à direita.
#
# --> [0, 1, 2, 3] & h
#       [h, 1, 2, 3] & 0
#       [h, 0, 2, 3] & 1
#       [h, 0, 10, 3] & 2
#       [h, 0, 10, 20] & 3
# <-- [30, 0, 10, 20] & h
def for_each_rot.go(~T: Type, ~C: Data, ~f: T -> @+a: C -> U32 -> T, k: Nat, r: Array<T> & T, +ctx: C, +src: U32) -> Array<T> & T:
  match k:
    case 0n:
      (arr, value) = r
      Array.swap(T, arr, 0, f(value, ctx, src))        # fecha o ciclo, devolve (arr, buraco)
    case 1n+p:
      (arr, value) = r
      +dst = (src + 1 : U32)
      for_each_rot.go(~T, ~C, ~f, p, Array.swap(T, arr, dst, f(value, ctx, src)), ctx, dst)

def for_each_rot.start(~T: Type, ~C: Data, ~f: T -> @+a: C -> U32 -> T, r: Array<T> & U32, hole: T, +ctx: C) -> Array<T> & T:
  (arr, +size) = r
  for_each_rot.go(~T, ~C, ~f, U32.to_nat((size - 1 : U32)), Array.swap(T, arr, 0, hole), ctx, 0)

def for_each_rot(~T: Type, ~C: Data, ~f: T -> @+a: C -> U32 -> T, arr: Array<T> & T, +ctx: C) -> Array<T> & T:
  (arr, hole) = arr
  for_each_rot.start(~T, ~C, ~f, Array.size(T, arr), hole, ctx)

# O mesmo truque do for_each_rot, mas com ACUMULADOR: a callback recebe o
# elemento, o acumulador e o índice de origem, e devolve a tupla
# (novo_elemento, novo_acumulador). É a passada de avaliação de um motor
# genético: transforma cada indivíduo e vai carregando o melhor.
#
# Medido no nativo (n = 2^20, 100 passadas): 0,4 ns por elemento — igual ao
# `reduce` (que só serve para elemento `Data`) e 47× mais rápido que o
# `reduce_consume` em árvore (18,8 ns). Devolver tupla na callback não custa
# nada: `Array.get` já devolve uma a cada chamada.
#
# Também ROTACIONA o array uma posição (mesmo motivo do for_each_rot).
# Devolve ((array, buraco), acumulador).
def fold_rot.put(~E: Type, ~S: Type, dst: Array<E>, +i: U32, r: E & S) -> (Array<E> & E) & S:
  (novo, acc) = r
  (Array.swap(E, dst, i, novo), acc)

def fold_rot.go(~E: Type, ~S: Type, ~C: Data, ~f: E -> S -> @+c: C -> U32 -> (E & S), k: Nat, st: (Array<E> & E) & S, +ctx: C, +src: U32) -> (Array<E> & E) & S:
  match k:
    case 0n:
      (ae, acc) = st
      (arr, held) = ae
      fold_rot.put(~E, ~S, arr, 0, f(held, acc, ctx, src))
    case 1n+p:
      (ae, acc) = st
      (arr, held) = ae
      +dst = (src + 1 : U32)
      fold_rot.go(~E, ~S, ~C, ~f, p, fold_rot.put(~E, ~S, arr, dst, f(held, acc, ctx, src)), ctx, dst)

def fold_rot.start(~E: Type, ~S: Type, ~C: Data, ~f: E -> S -> @+c: C -> U32 -> (E & S), r: Array<E> & U32, hole: E, acc: S, +ctx: C) -> (Array<E> & E) & S:
  (arr, +n) = r
  fold_rot.go(~E, ~S, ~C, ~f, U32.to_nat((n - 1 : U32)), (Array.swap(E, arr, 0, hole), acc), ctx, 0)

def fold_rot(~E: Type, ~S: Type, ~C: Data, ~f: E -> S -> @+c: C -> U32 -> (E & S), arr: Array<E> & E, acc: S, +ctx: C) -> (Array<E> & E) & S:
  (arr, hole) = arr
  fold_rot.start(~E, ~S, ~C, ~f, Array.size(E, arr), hole, acc, ctx)

# Tudo bem, se vai transformar em string é lento mesmo então pode ser usando match
def show.go(~T: Type, ~fn: T -> String, arr: Array<T>) -> String:
  match arr:
    case ALeaf{x}:
      fn(x)
    case ANode{xs, ys}:
      show.go(~T, ~fn, xs) ++ ", " ++ show.go(~T, ~fn, ys)

def show(~T: Type, ~fn: T -> String, arr: Array<T>) -> String:
  "[" ++ show.go(~T, ~fn, arr) ++ "]"