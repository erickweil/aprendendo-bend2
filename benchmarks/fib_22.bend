import Base
def fib(+n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n:
      1n
    case 2n+p:
      fib(p) + fib(1n+p)
def main() -> IO(Unit):
  IO.print("fib(22n) = " ++ Nat.show(fib(22n)))
