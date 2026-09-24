import Base
import ./../utils/io.bend as IOU
import ./../utils/arrays.bend as Arr

# ARRAYS: memória contínua com leitura e escrita O(1) no lugar.
#
# Um `Array<T>` é um `Type`, não um `Data`: tem exatamente UM dono e não
# aceita `+`. É isso que permite escrever no lugar sem cópia. O preço: uma
# operação que só LÊ precisa devolver o array junto com a resposta:
#
#   a[5]                     -> Array<U32> & U32
#   Array.get(T, a, i)       -> Array<T> & T
#   Array.size(T, a)         -> Array<T> & U32
#   Array.clone(T, a)        -> Array<T> & Array<T>
#
# O tamanho é sempre potência de 2 e os índices dão a volta (a[8] é a[0]
# num array de 8 posições). `a[i]` e `a[i] <- v` só existem para U32; para
# outros tipos, `Array.get` e `Array.set`.

# O laço clássico, escrito à mão: o par da leitura anterior é o ESTADO do
# laço, e é aberto dentro de cada caso. Soma a[0] + ... + a[k].
def soma(k: Nat, r: Array<U32> & U32, +i: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      (a, v) = r
      (acc + v : U32)
    case 1n+p:
      (a, v) = r
      soma(p, Array.get(U32, a, (i + 1 : U32)), (i + 1 : U32), (acc + v : U32))

# O mesmo com utils/arrays.bend: a callback recebe (elemento, contexto, índice)
def quadrado(x: U32, +ctx: U32, i: U32) -> U32:
  +j = i
  (j * j % ctx : U32)

def mais(+x: U32, acc: U32, i: U32) -> U32:
  (acc + x : U32)

def fecha_soma(r: Array<U32> & U32) -> U32:
  (a, s) = r
  s

def dobro(x: U32) -> U32:
  (2 * x : U32)

# Um par `(array, valor)` só pode ser aberto como PARÂMETRO. O array volta
# junto com o valor lido, e pode seguir sendo usado.
def basico.fim(r: Array<U32> & U32) -> IO(Unit):
  (a, v) = r
  IO.print("a[5] = " ++ U32.show(v) ++ ", soma de tudo = " ++ U32.show(soma(7n, Array.get(U32, a, 0), 0, 0)))

def basico() -> IO(Unit):
  a = [0 : U32*8n]            # 8 posições com 0 (também: [0 : U32^3n])
  a[5] <- 42                  # escreve no lugar (a = Array.set(U32, a, 5, 42))
  a[1] <- 7
  basico.fim(a[5])            # lê: devolve (a, 42)

# Uso: arrays [profundidade=20]   (um array de 2^profundidade posições)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +d : U32 = IOU.num_at(IOU.numbers(args), 0n, 20)
    basico()
    t0 : Nat <- IO.now()
    a : Array<U32> = Array.new(U32, U32.to_nat(d), 0)
    a : Array<U32> = Arr.for_each(~U32, ~U32, ~quadrado, a, 1000)   # a[i] = i² mod 1000
    a : Array<U32> = Array.map(~U32, ~U32, ~dobro, a)              # da Base: um array novo
    IO.print("soma de 2·(i² mod 1000) em 2^" ++ U32.show(d) ++ " posições: " ++
      U32.show(fecha_soma(Arr.reduce(~U32, ~U32, ~mais, a, 0))))
    dt : String <- IOU.tempo_desde(t0)
    IO.print("  " ++ dt)
