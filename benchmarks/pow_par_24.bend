import Base
def pow2(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a b = pow2(p) pow2(p)
      (a + b : U32)
def main() -> IO(Unit):
  IO.print("2^24 = " ++ U32.show(pow2(24n)))
