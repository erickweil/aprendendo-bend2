import Base

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
      fib(p) + fib(1n+p)

# Fibonacci iterativo, usando iter para contagem recursiva
def fib_iter(+iter: Nat, +a: U32, +b: U32) -> U32:
  match iter:
    # Caso base, retorna o valor de a
    case 0n:
      a
    # Separa iter em um pedaço menor p (igual a iter - 1)
    case 1n+p:
      fib_iter(p, b, (a + b : U32))

def qual() -> Nat:
  10n

def main() -> IO(Unit):  
  +n = qual()
  f_nat = fib(n)
  f_u32 = fib_iter(n, 0, 1)

  do IO<Unit>:
    # Observe que a execução é lazy. Só quando o valor é necessário ele é computado...
    u : Unit <- IO.print("Calculando Fibonacci Nº " ++ Nat.show(n) ++ "...")
    # As linhas abaixo demoram aparecer pois o cálculo só acontece agora que precisa exibir o valor
    u : Unit <- IO.print(Nat.show(n) ++ "º --> " ++ U32.show(f_u32) ++ " (U32)")
    # O cálculo usando Nat é muito mais lento por ser método recursivo 2^n e também por usar aritmética Nat
    u : Unit <- IO.print(Nat.show(n) ++ "º --> " ++ Nat.show(f_nat) ++ " (Nat)")

    IO.print("Finalizado")