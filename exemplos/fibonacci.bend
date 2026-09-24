import Base
import ./../utils/io.bend as IOU

# Fibonacci recursivo com Nat e match, onde cada chamada é um pedaço menor da chamada anterior
def fib(+n: Nat) -> U32:
  match n:
    # Casos base, 0 e 1
    case 0n:
      0
    case 1n:
      1
    # Separa n em um pedaço menor p (igual a n - 2) 
    case 2n+p:
      # Chama recursivamente, usando o pedaço p que é n-2 e cria um pedaço 1n+p que é n-1
      f1 f2 = fib(p) fib(1n+p)
      (f1 + f2 : U32)

# Fibonacci iterativo, usando iter para contagem recursiva
def fib_iter(+iter: Nat, +a: U32, +b: U32) -> U32:
  match iter:
    # Caso base, retorna o valor de a
    case 0n:
      a
    # Separa iter em um pedaço menor p (igual a iter - 1)
    case 1n+p:
      fib_iter(p, b, (a + b : U32))

# Sim isso é ridículo está re-calculando o número denovo toda vez, mas é só para mostrar a diferença de performance entre o método recursivo e o iterativo
def loop(n: Nat, +qual: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.print("Fim do loop")
    case 1n+p:
      do IO<Unit>:
        # O cálculo usando Nat é muito mais lento por ser método recursivo 2^n e também por usar aritmética Nat
        v : U32 = fib(U32.to_nat(qual))
        IO.print(U32.show(v))
        loop(p, (qual + 1 : U32))

# Uso: fibonacci [n=30]    (compare --threads 1 e --threads 8 no binário)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOU.num_at(IOU.numbers(args), 0n, 30)
    loop(U32.to_nat(U32.min(n, 20)), 0)
    t0 : Nat <- IO.now()
    IO.print("F(" ++ U32.show(n) ++ ") iterativo = " ++ U32.show(fib_iter(U32.to_nat(n), 0, 1)))
    dt0 : String <- IOU.tempo_desde(t0)
    IO.print("  " ++ dt0)
    t1 : Nat <- IO.now()
    IO.print("F(" ++ U32.show(n) ++ ") recursivo = " ++ U32.show(fib(U32.to_nat(n))))
    dt1 : String <- IOU.tempo_desde(t1)
    IO.print("  " ++ dt1)
