import Base
import ./../utils/io.bend as IOUtils

# Usando recursividade podemos sim ter uma repetição, mas loop infinito não compila
# Experimenta descomentar isso aqui:
# def infinito(n: Nat) -> Nat:
#   infinito(n)

# Só é possível ter recursividade se o compilador consegue provar que a função irá parar eventualmente
# O tipo Nat (Natural) é usado aqui de forma a cada chamada ser um pedaço p (1n+p) da chamada anterior, que eventualmente chegará em 0n
def repetir(+n: Nat) -> IO(Unit):
  match n:
    case 0n:
      IO.print("Fim da repetição")
    case 1n+p:
      IO.bind(Unit, Unit, IO.print(Nat.show(1n+p)), _ => repetir(p))
      
# A parte da contagem de repetição TEM que ser Nat, mas o resto das operações pode ser U32
def somar_todos(+n: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      n_u32 = U32.from_nat(p)
      somar_todos(p, (acc + n_u32 + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +v : U32 = IOUtils.num_at(IOUtils.numbers(args), 0n, 10)
    u : Unit <- repetir(U32.to_nat(v))
    IO.print("A soma de todos é:" ++ U32.show(somar_todos(U32.to_nat(v), 0)))
  