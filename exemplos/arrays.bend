import Base
import ./../utils/arrays.bend as Arr
# Arrays em Bend 2
# ================
#
# Um Array<T> é um `Type`, não um `Data`: ele tem exatamente UM dono e não
# aceita `+` pois só pode ser consumido UMA vez, mas tem performance O(1)
# 
# a[i] <- v é a mesma coisa que `a = Array.set(T, a, i, v)` (Rebinding)
# 
# O preço é que toda operação que só quer LER o array precisa devolvê-lo
# junto com a resposta, num par `Array<T> & R`:
#
#   a[5]                  -> Array<U32> & U32
#   Array.size(U32, a)    -> Array<U32> & U32
#   Array.clone(U32, a)   -> Array<U32> & Array<U32>
#
# Por dentro (veja base.bend) o Array é uma árvore binária completa, por isso
# o tamanho é sempre uma potência de 2 ([0 : U32*8n] ou [0 : U32^3n]) e os
# índices dão a volta (a[8] é a[0] num array de 8):
#
#   type Array<-T: Type> is Type:
#     ALeaf{value: T}
#     ANode{xs: Array<T>, ys: Array<T>}
#

def demo_basico() -> IO(Unit):
  a = [0 : U32*8n]
  # Chama callback para cada elemento retornando novo valor
  a = Arr.for_each(~U32, ~(x => i => 
    (i * i : U32)
  ), a)
  # In place write
  a[1] <- 42
  # índices dão a volta: 8 % 8 = 0
  a[8] <- 67

  Arr.with(U32, U32, IO(Unit), a[5], a => +v =>
  Arr.with(U32, U32, IO(Unit), Array.size(U32, a), a => +n =>
  do IO<Unit>:
    u : Unit <- IO.print("== básico ==")
    u : Unit <- IO.print(Arr.show(~U32, ~U32.show, a))
    u : Unit <- IO.print("a[5]   = " ++ U32.show(v))
    IO.print("len    = " ++ U32.show(n))
  ))

def demo_arrays() -> IO(Unit):
  # Gera um array com 2^6 = 64 elementos, cada um valendo 1
  arr = [1 : U32^6n]
  # Função que irá somar todos os valores, sem perder o array
  arr_soma = Arr.reduce(~U32, ~U32, ~(x => acc => (x + acc : U32)), arr, 0)
  Arr.with(U32, U32, IO(Unit), arr_soma, arr => +soma =>
  do IO<Unit>:
    u : Unit <- IO.print("== arrays ==")
    u : Unit <- IO.print(Arr.show(~U32, ~U32.show, arr))
    IO.print("soma = " ++ U32.show(soma))
  )

def main() -> IO(Unit):
  do IO<Unit>:
    u : Unit <- demo_basico()
    u : Unit <- demo_arrays()
    IO.print("== fim ==")
