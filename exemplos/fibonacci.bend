import Base
import ./../utils/io.bend as IOUtils

# Fibonacci recursivo com Nat e match, onde cada chamada é um pedaço menor da chamada anterior
def fib(+n: Nat) -> Nat:
  match n:
    # Casos base, 0 e 1
    case 0n:
      0n
    case 1n:
      1n
    # Separa n em um pedaço menor p (igual a n - 2) 
    case 2n+p:
      # Chama recursivamente, usando o pedaço p que é n-2 e cria um pedaço 1n+p que é n-1
      f1 f2 = fib(p) fib(1n+p)
      (f1 + f2 : Nat)

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
      # O cálculo usando Nat é muito mais lento por ser método recursivo 2^n e também por usar aritmética Nat
      v = fib(U32.to_nat(qual))
      IO.bind(Unit, Unit, IO.print(Nat.show(v)), _ => loop(p, (qual + 1 : U32)))

      # O cálculo usando U32 é muito mais rápido por ser método iterativo
      # v = fib_iter(U32.to_nat(qual), 0, 1)
      #IO.bind(Unit, Unit, IO.print(U32.show(v)), _ => loop(p, (qual + 1 : U32)))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOUtils.num_at(IOUtils.numbers(args), 0n, 10)

    u : Unit <- IO.print("Calculando Fibonacci Nº " ++ U32.show(n) ++ "...")
    loop(U32.to_nat(n), 1)