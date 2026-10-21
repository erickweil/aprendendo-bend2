import Base
import ./../utils/io.bend as IOU

# PARALELISMO: a chamada paralela `a b = f(x) g(y)` promete ao compilador
# que as duas chamadas são independentes (sempre verdade: Bend é puro) e
# levam mais ou menos o mesmo tempo (isso é com você). Cada uma vira uma
# tarefa, e as tarefas são distribuídas entre os núcleos.
#
# Esta deve ser a pior forma que existe de calcular 2^n: soma 1 + 1 + ...
# 2^n vezes, numa árvore de chamadas. Justamente por isso é um bom teste de
# paralelismo: 2^n folhas de trabalho idêntico e nenhuma memória.
def pow2(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a b = pow2(p) pow2(p)
      (a + b : U32)

# O mesmo trabalho em duas linhas: é SEQUENCIAL. O Bend não paraleliza
# sozinho, só onde está escrito `a b = ..`.
def pow2_seq(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a = pow2_seq(p)
      b = pow2_seq(p)
      (a + b : U32)

# Uso: pow [n=24]
#   bend pow.bend -o ../bin/pow
#   ../bin/pow 28 --threads 1     (compare com --threads 4, 8, 12)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOU.num_at(IOU.numbers(args), 0n, 24)
    t0 : Nat <- IO.now()
    IO.print("paralelo:    2^" ++ U32.show(n) ++ " = " ++ U32.show(pow2(U32.to_nat(n))))
    dt0 : String <- IOU.tempo_desde(t0)
    IO.print("  " ++ dt0)
    t1 : Nat <- IO.now()
    IO.print("sequencial:  2^" ++ U32.show(n) ++ " = " ++ U32.show(pow2_seq(U32.to_nat(n))))
    dt1 : String <- IOU.tempo_desde(t1)
    IO.print("  " ++ dt1)
    # `!` entrega a chamada (e todas as chamadas paralelas dentro dela) à
    # GPU. Sem GPU (ou com --gpu off) ela roda na CPU, em paralelo.
    t2 : Nat <- IO.now()
    IO.print("na GPU (!):  2^" ++ U32.show(n) ++ " = " ++ U32.show(pow2!(U32.to_nat(n))))
    dt2 : String <- IOU.tempo_desde(t2)
    IO.print("  " ++ dt2)
