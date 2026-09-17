import Base

def soma_split(cond: Bool, a: U32, b: U32) -> U32:
  match cond:
    case True{}:
      a
    case False{}:
      mid = ((a + b : U32) / 2 : U32)
      x y = soma_range(a, mid) soma_range((mid + 1 : U32), b)
      (x + y : U32)

@unsafe
def soma_range(+a: U32, +b: U32) -> U32:
  soma_split(U32.is_ge(a, b), a, b)

def main() -> IO(Unit):
  IO.print("Soma: " ++ U32.show(soma_range(1, 100)))
