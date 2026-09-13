import Base

def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

def eh_divisivel(n: U32, d: U32) -> Bool:
  U32.is_zero((n % d : U32))

def eh_primo_check(combustivel: Nat, +i: U32, +num: U32) -> Bool:
  match combustivel:
    case 0n:
      True{}
    case 1n+p:
      # Irá parar se i*i > num: pois se não achou divisor até a raiz, não acha mais
      pick(Bool, (i > num / i : U32),
        True{},
        pick(Bool, eh_divisivel(num, i),
          False{},
          eh_primo_check(p, (i + 2 : U32), num)))

def eh_primo(+num: U32) -> Bool:
  # 2 é primo
  pick(Bool, U32.is_eq(num, 2), 
    True{},
    # números menores que 2 e pares não são primos
    pick(Bool, U32.is_lt(num, 2) || eh_divisivel(num, 2), 
      False{},
      eh_primo_check(U32.to_nat(num), 3, num)
    )
  ) 

# Checando se um número é primo ou não
def numero() -> U32:
  11

def main() -> IO(Unit):
  IO.print(pick(String, eh_primo(numero()), "Primo", "Não é primo"))