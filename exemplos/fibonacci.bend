import Base
import ./../utils/io.bend as IOU

# FIBONACCI de dois jeitos: a recursão dupla (exponencial, mas paralela) e
# o laço com acumuladores (linear).

# F(n) = F(n-1) + F(n-2). `2n+p` separa n em "2 mais p": p é n-2 e `1n+p` é
# n-1, dois pedaços menores de n, então o compilador sabe que termina. As
# duas chamadas são independentes e viram tarefas paralelas.
def fib(+n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n:
      1
    case 2n+p:
      a b = fib(1n+p) fib(p)
      (a + b : U32)

# O mesmo com dois acumuladores: (a, b) anda para (b, a + b) a cada passo.
# A chamada recursiva é a última coisa feita (tail call), e vira um laço.
def fib_iter(k: Nat, +a: U32, +b: U32) -> U32:
  match k:
    case 0n:
      a
    case 1n+p:
      fib_iter(p, b, (a + b : U32))

# Imprime F(0), F(1), ..., F(k-1)
def sequencia(k: Nat, +i: U32) -> IO(Unit):
  match k:
    case 0n:
      IO.print("")
    case 1n+p:
      do IO<Unit>:
        IO.write(U32.show(fib_iter(U32.to_nat(i), 0, 1)) ++ " ")
        sequencia(p, (i + 1 : U32))

# Uso: fibonacci [n=30]    (dá a volta no U32 acima de F(47))
#   bend fibonacci.bend -o ../bin/fibonacci
#   ../bin/fibonacci 40 --threads 1        (compare com --threads 12)
#
# A recursão faz ~1,6^n chamadas: F(40) são 330 milhões. Medido no nativo,
# 12 threads calculam 4× mais rápido que 1; o laço faz 40 passos e leva 0 ms.
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOU.num_at(IOU.numbers(args), 0n, 30)
    sequencia(15n, 0)
    t0 : Nat <- IO.now()
    IO.print("F(" ++ U32.show(n) ++ ") com o laço     = " ++ U32.show(fib_iter(U32.to_nat(n), 0, 1)))
    dt0 : String <- IOU.tempo_desde(t0)
    IO.print("  " ++ dt0)
    t1 : Nat <- IO.now()
    IO.print("F(" ++ U32.show(n) ++ ") com a recursão = " ++ U32.show(fib(U32.to_nat(n))))
    dt1 : String <- IOU.tempo_desde(t1)
    IO.print("  " ++ dt1)
