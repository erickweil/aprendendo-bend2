import Base
import ./../utils/tuples.bend as T
import ./../utils/arrays.bend as Arr
import ./../utils/io.bend as IOUtils
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

def demo_basico(quantos: U32) -> IO(Unit):
  T.run_state_consume(Array<U32>, IO(Unit),
    (do T.State<Array<U32>, IO(Unit)>:
      size : U32  <- arr => Array.size(U32, arr)

      _: Unit     <- arr => (Arr.for_each(~U32, ~U32, ~(value => size => i => 
        (size - i : U32)
      ), arr, size), Unit{})

      sum : U32   <- arr => Arr.reduce(~U32, ~U32, ~(value => acc => i => 
        (acc + value : U32)
      ), arr, 0)

      arr_str : String <- arr => Arr.reduce(~U32, ~String, ~(value => acc => i =>
        acc ++ " " ++ U32.show(value)
      ), arr, "Array:")
      
      return IO.print(arr_str ++ ", sum: " ++ U32.show(sum))
    ), 
    Array.new(U32, U32.to_nat(quantos), 0)
  )

def sum_array(value: U32, arr: Array<U32> & U32) -> Array<U32> & U32:
  (arr, sum) = arr
  Arr.reduce(~U32, ~U32, ~(x => sum => i => (x + sum : U32)), arr, sum)

def demo_arrays(quantos: U32) -> IO(Unit):
  # Gera um array com 2^10 = 1024 elementos, cada um valendo 1
  arr = Array.new(U32, U32.to_nat(quantos), 1)
  arr_copy = Array.clone(U32, arr)
  Arr.with(U32, Array<U32>, IO(Unit), arr_copy, arr => copy =>
    # Isso é um for com outro for dentro. 1024 * 1024 = 1M
    copy_sum = Arr.reduce_consume(~U32, ~(Array<U32> & U32), ~sum_array, arr, (copy, 0))
    Arr.with(U32, U32, IO(Unit), copy_sum, copy => +sum =>
      do IO<Unit>:
        u : Unit <- IO.print("== arrays ==")
        IO.print("soma: " ++ U32.show(sum))
    )
  )

def main() -> IO(Unit):
  do IO<Unit>:
    u: Unit <- IO.print("== início ==")
    args : List<String> <- IO.args()
    +numbers : List<&2, Maybe<&2, U32>> = IOUtils.numbers(args)
    +quantos : U32 = IOUtils.num_at(numbers, 0n, 5)

    u: Unit <- demo_basico(quantos)
    #u : Unit <- demo_arrays(quantos)
    IO.print("== fim ==")