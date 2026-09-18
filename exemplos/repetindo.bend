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
    case 1n+ +p:
      repetir(p, acc ++ Nat.show(p + 1n) ++ "\n")
      
# A parte da contagem de repetição TEM que ser Nat, mas o resto das operações pode ser U32
def somar_todos(+n: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+ +p:
      n_u32 = U32.from_nat(p)
      somar_todos(p, (acc + n_u32 + 1 : U32))

# Defina até quanto contar (padrão se não informado via CLI)
def valor() -> Nat:
  5n

def parse_nat(m: Maybe<&2, Nat>, default: Nat) -> Nat:
  match m:
    case None{}: default
    case Some{val}: val

def get_arg_nat(args: List<String>, default: Nat) -> Nat:
  match args:
    case Nil{}: default
    case Con{first, rest}:
      parse_nat(Nat.read(first), default)

def run(args: List<String>) -> IO(Unit):
  +v = get_arg_nat(args, valor())
  msg = repetir(v, "")
  soma = somar_todos(v, 0)
  IO.print(msg ++ "A soma de todos é:" ++ U32.show(soma))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
  