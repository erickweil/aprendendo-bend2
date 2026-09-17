import Base

# Usando recursividade podemos sim ter uma repetição, mas loop infinito não compila
# Experimenta descomentar isso aqui:
# def infinito(n: Nat) -> Nat:
#   infinito(n)

# Só é possível ter recursividade se o compilador consegue provar que a função irá parar eventualmente
# O tipo Nat (Natural) é usado aqui de forma a cada chamada ser um pedaço p (1n+p) da chamada anterior, que eventualmente chegará em 0n
def repetir(n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      +p = p
      repetir(p, acc ++ Nat.show(p + 1n) ++ "\n")
      
# A parte da contagem de repetição TEM que ser Nat, mas o resto das operações pode ser U32
def somar_todos(+n: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      n_u32 = U32.from_nat(p)
      somar_todos(p, (acc + n_u32 + 1 : U32))

# Defina até quanto contar
def valor() -> Nat:
  500n

def main() -> IO(Unit):
  msg = repetir(valor(), "")
  soma = somar_todos(valor(), 0)
  
  IO.print(msg ++ "A soma de todos é:" ++ U32.show(soma))
  