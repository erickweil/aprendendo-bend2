import Base
import ./../utils/io.bend as IOU

# Fibonacci recursivo: F(n) = F(n-1) + F(n-2). O padrão `2n+p` separa n em
# "2 mais p", então p é n-2 e `1n+p` é n-1 — dois pedaços menores de n.
# As duas chamadas são independentes e rodam em paralelo.
# É exponencial (~1,6^n chamadas): lento de propósito. Medido no nativo,
# F(40) leva 0,54 s com 1 thread (~1,6 ns por chamada) e 0,14 s com 12.
def fib(+n: Nat) -> U32:
  match n:
    case 0n: 0
    case 1n: 1
    case 2n+ +p:
      f1 f2 = fib(1n+p) fib(p)
      (f1 + f2 : U32)

# Fibonacci iterativo: carrega o par (a, b) e anda n passos. Linear.
def fib_iter(n: Nat, +a: U32, +b: U32) -> U32:
  match n:
    case 0n: a
    case 1n+p: fib_iter(p, b, (a + b : U32))

# Imprime F(0), F(1), ... F(n-1) com a versão iterativa
def listar(k: Nat, +i: U32) -> IO(Unit):
  match k:
    case 0n:
      IO.print("")
    case 1n+p:
      do IO<Unit>:
        IO.write(U32.show(fib_iter(U32.to_nat(i), 0, 1)) ++ " ")
        listar(p, (i + 1 : U32))

# Uso: fibonacci [n=30]    (compare --threads 1 e --threads 8 no binário)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOU.num_at(IOU.numbers(args), 0n, 30)
    listar(U32.to_nat(U32.min(n, 20)), 0)
    t0 : Nat <- IO.now()
    IO.print("F(" ++ U32.show(n) ++ ") iterativo = " ++ U32.show(fib_iter(U32.to_nat(n), 0, 1)))
    dt0 : String <- IOU.tempo_desde(t0)
    IO.print("  " ++ dt0)
    t1 : Nat <- IO.now()
    IO.print("F(" ++ U32.show(n) ++ ") recursivo = " ++ U32.show(fib(U32.to_nat(n))))
    dt1 : String <- IOU.tempo_desde(t1)
    IO.print("  " ++ dt1)
