import Base

def soma_seq(+fuel: Nat, +a: U32, +b: U32) -> U32:
  match fuel:
    case 0n:
      a
    case 1n+p:
      Bool.pick(U32, U32.is_ge(a, b),
        a,
        (a + soma_seq(p, (a + 1 : U32), b) : U32))

def soma_par(+d: Nat, +a: U32, +b: U32) -> U32:
  match d:
    case 0n:
      soma_seq(U32.to_nat((b - a + 1 : U32)), a, b)
    case 1n+p:
      +mid = ((a + b : U32) / 2 : U32)
      x y = soma_par(p, a, mid) soma_par(p, (mid + 1 : U32), b)
      (x + y : U32)

def main() -> IO(Unit):
  # 1 + 2 + 3 + ... + 8 = 36
  IO.print("Soma: " ++ U32.show(soma_par(3n, 1, 8)))
