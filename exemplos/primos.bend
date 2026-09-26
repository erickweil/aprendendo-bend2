import Base
import ./../utils/io.bend as IOU

# CONTAR PRIMOS EM PARALELO, por divisão por tentativa.

def divide(+n: U32, +d: U32) -> Bool:
  U32.is_zero((n % d : U32))

# Testa os divisores até a raiz de n. Depois de 2 e 3, basta testar os da
# forma 6k ± 1 (5, 7, 11, 13, 17, 19, ...): os outros são múltiplos de 2 ou
# de 3. O passo alterna entre 2 e 4, e são 2 divisores a cada 6 números, um
# terço dos que os ímpares seriam.
#
# Parar no PRIMEIRO divisor exige cuidado: `Bool.pick(Bool, divide(n, d),
# False{}, primo.go(..))` calcularia a recursão de qualquer jeito (é
# estrito). Então a condição do passo ANTERIOR entra como parâmetro
# (`achou`), e o caso `True{}` devolve sem recursão (AGENTS.md, Armadilha 2).
# `k` é quantos divisores faltam.
def primo.go(k: Nat, achou: Bool, +d: U32, +passo: U32, +n: U32) -> Bool:
  match k achou:
    case _ True{}: False{}
    case 0n False{}: True{}
    case 1n+p False{}: primo.go(p, divide(n, d), (d + passo : U32), (6 - passo : U32), n)

# Raiz quadrada inteira via F32 (+1 de folga para o arredondamento)
def raiz(+n: U32) -> U32:
  (F32.to_u32(F32.sqrt(U32.to_f32(n))) + 1 : U32)

def primo(+n: U32) -> Bool:
  match n:
    case 0: False{}
    case 1: False{}
    case 2: True{}
    case 3: True{}
    case _:
      # quantos números 6k - 1 e 6k + 1 há de 5 até a raiz r
      +r = raiz(n)
      primo.go(U32.to_nat(((r + 1) / 6 + (r - 1) / 6 : U32)), divide(n, 2) || divide(n, 3), 5, 2, n)

# Conta os primos em [i, i + k), um por vez
def contar.seq(k: Nat, +i: U32, +acc: U32) -> U32:
  match k:
    case 0n: acc
    case 1n+p: contar.seq(p, (i + 1 : U32), (acc + Bool.to_u32(primo(i)) : U32))

# Divide o intervalo [lo, hi) ao meio `prof` vezes e conta as partes em
# paralelo: 2^prof tarefas. Os números altos custam mais (a raiz é maior),
# então mais tarefas que núcleos ajudam a equilibrar a carga. Medido no
# nativo, primos abaixo de 20 milhões (i5-1245U na bateria, 12 threads):
#
#   prof = 0  (1 tarefa)     5,65 s
#   prof = 3  (8 tarefas)    2,72 s   2,1×
#   prof = 6  (64 tarefas)   1,77 s   3,2×   <- o teto desta máquina
#   prof = 10 (1024)         1,75 s
#
# (Testar só 6k ± 1 deixou cada tarefa 1,46× mais rápida que testar todos
# os ímpares: 8,2 s -> 5,6 s com 1 tarefa.)
def contar(prof: Nat, +lo: U32, +hi: U32) -> U32:
  match prof:
    case 0n: contar.seq(U32.to_nat((hi - lo : U32)), lo, 0)
    case 1n+ +p:
      +meio = (lo + (hi - lo) / 2 : U32)
      a b = contar(p, lo, meio) contar(p, meio, hi)
      (a + b : U32)

# Uso: primos [n=100000] [prof=6]
#   bend primos.bend -o ../bin/primos
#   ../bin/primos 10000000 --threads 1      (compare com --threads 4, 8, 12)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +n : U32 = IOU.num_at(ns, 0n, 100000)
    t0 : Nat <- IO.now()
    IO.print("primos abaixo de " ++ U32.show(n) ++ ": " ++ U32.show(contar(U32.to_nat(IOU.num_at(ns, 1n, 6)), 0, n)))
    dt : String <- IOU.tempo_desde(t0)
    IO.print("  " ++ dt)
