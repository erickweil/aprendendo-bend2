# Experimentos isso nem funciona kk
import Base

def max_u32() -> U32:
  4294967295

# 'for loop' funcional, chama a função f recursivamente n vezes.
#
# repetir(~S, ~f, 3n, e)  ==  f(f(f(e)))
def repetir(~S: Type, ~f: S -> S, n: Nat, estado: S) -> S:
  match n:
    case 0n:
      estado
    case 1n+p:
      repetir(~S, ~f, p, f(estado))

def power2(expoente: Nat) -> U32:
  repetir(~U32, ~(x => (2 * x : U32)), expoente, 1)

# def pow.f(bx: U32 & U32) -> U32 & U32:
#   (b, x) = bx
#   +b = b
#   (b, (b * x : U32))

# def pow(base: U32, expoente: Nat) -> U32 & U32:
#   repetir(~(U32 & U32), ~pow.f, expoente, (base, 1))

def main() -> IO(Unit):
  resultado = power2(10n)
  IO.print(U32.show(resultado))