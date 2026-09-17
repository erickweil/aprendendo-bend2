import Base

def eh_div(n: U32, d: U32) -> Bool:
  U32.is_zero((n % d : U32))

def tem_divisor_seq(+combustivel: Nat, +n: U32, +cur: U32, +fim: U32) -> Bool:
  match combustivel:
    case 0n:
      False{}
    case 1n+p:
      Bool.pick(Bool, (cur > fim : U32),
        False{},
        Bool.pick(Bool, eh_div(n, cur),
          True{},
          tem_divisor_seq(p, n, (cur + 2 : U32), fim)))

def tem_divisor_par(+d: Nat, +n: U32, +min: U32, +max: U32) -> Bool:
  match d:
    case 0n:
      tem_divisor_seq(U32.to_nat(((max - min) / 2 + 2 : U32)), n, min, max)
    case 1n+p:
      +meio = ((min + max) / 2 : U32)
      esq dir = tem_divisor_par(p, n, min, meio) tem_divisor_par(p, n, (meio + 1 : U32), max)
      esq || dir

def num() -> U32:
  2147483647

def lim() -> U32:
  46340

def main() -> IO(Unit):
  tem_div = tem_divisor_par(6n, num(), 3, lim())
  IO.print(Bool.pick(String, tem_div, "Composto (não primo)", "Primo de Mersenne confirmado!"))
