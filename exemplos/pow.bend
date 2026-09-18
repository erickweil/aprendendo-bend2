import Base

def pow2(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a b = pow2(p) pow2(p)
      (a + b : U32)

# Mesmo trabalho de A, porém sem a chamada paralela.
# Sim essa deve ser a pior forma que existe de calcular 2^n
def pow2_seq(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a = pow2_seq(p)
      b = pow2_seq(p)
      (a + b : U32)

def parse_u32(m: Maybe<&2, U32>, default: U32) -> U32:
  match m:
    case None{}: default
    case Some{val}: val

def get_arg_u32(args: List<String>, default: U32) -> U32:
  match args:
    case Nil{}: default
    case Con{first, rest}:
      parse_u32(U32.read(first), default)

def run(args: List<String>) -> IO(Unit):
  # Escolha com sabedoria, números altos podem estourar a memória com gigabytes de dados (padrão se não informado via CLI)
  +n = get_arg_u32(args, 8)
  do IO<Unit>:
    u: Unit <- IO.print("Calculando 2^" ++ U32.show(n) ++ " com chamadas paralelas")
    u: Unit <- IO.print(U32.show(pow2(U32.to_nat(n))))

    u: Unit <- IO.print("Calculando 2^" ++ U32.show(n) ++ " com chamadas sequenciais")
    u: Unit <- IO.print(U32.show(pow2_seq(U32.to_nat(n))))

    IO.print("fim")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
