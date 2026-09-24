import Base
import ./../utils/io.bend as IOU
import ./../utils/arrays.bend as Arr
import ./../utils/math.bend as M

# CRIVO DE ERATÓSTENES: um array em que a[i] = 1 marca "i não é primo".
# Para cada primo i (de 2 até a raiz de n), risca i², i² + i, i² + 2i, ...
# É um exemplo de laços ANINHADOS sobre um array, escritos como recursões
# com combustível (`Nat`) e o array passado de mão em mão.

# Risca k posições: j, j + passo, j + 2·passo, ...
def riscar(k: Nat, a: Array<U32>, +j: U32, +passo: U32) -> Array<U32>:
  match k:
    case 0n: a
    case 1n+p: riscar(p, Array.set(U32, a, j, 1), (j + passo : U32), passo)

# Se i é primo, risca os múltiplos de i a partir de i² (os menores já foram
# riscados por primos menores). São ceil((n - i²) / i) posições.
def riscar.se(primo: Bool, a: Array<U32>, +i: U32, +n: U32) -> Array<U32>:
  match primo:
    case False{}: a
    case True{}: riscar(U32.to_nat(((n - i * i + i - 1) / i : U32)), a, (i * i : U32), i)

# O par `(a, a[i])` da leitura é o parâmetro; um auxiliar não recursivo o abre
def passo(r: Array<U32> & U32, +i: U32, +n: U32) -> Array<U32>:
  (a, v) = r
  riscar.se(U32.is_zero(v) && (i * i < n : U32), a, i, n)

# O laço de fora: i = 2, 3, ..., 2 + k - 1
def crivo(k: Nat, a: Array<U32>, +i: U32, +n: U32) -> Array<U32>:
  match k:
    case 0n: a
    case 1n+p: crivo(p, passo(Array.get(U32, a, i), i, n), (i + 1 : U32), n)

# Conta os zeros de [2, n): cada um é um primo
def conta(+x: U32, acc: U32, +k: U32) -> U32:
  (acc + Bool.to_u32(U32.is_zero(x)) : U32)

def total(r: Array<U32> & U32) -> U32:
  (a, s) = r
  s

def primos_abaixo(+n: U32) -> U32:
  +r = F32.to_u32(F32.sqrt(U32.to_f32(n)))
  a = crivo(U32.to_nat(r), [0 : U32^M.log2_ceil(n)], 2, n)
  total(Arr.fold_range(~U32, ~U32, ~conta, a, 0, 2, (n - 2 : U32)))

# Medido no nativo: primos abaixo de 20 milhões em 0,23 s, num núcleo só. O
# `primos.bend` (divisão por tentativa) leva 1,0 s com 12 threads: o
# algoritmo certo vale mais que o paralelismo. O custo é memória: 4 bytes por
# número (100 milhões pedem um array de 2^27 posições, 512 MB).
#
# Uso: crivo [n=100000]
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = U32.max(IOU.num_at(IOU.numbers(args), 0n, 100000), 2)
    t0 : Nat <- IO.now()
    IO.print("primos abaixo de " ++ U32.show(n) ++ ": " ++ U32.show(primos_abaixo(n)))
    dt : String <- IOU.tempo_desde(t0)
    IO.print("  " ++ dt)
