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

# Escolha com sabedoria, números altos podem estourar a memória com gigabytes de dados
def numero() -> U32:
  12

def main() -> IO(Unit):
  do IO<Unit>:
    u: Unit <- IO.print("Calculando 2^" ++ U32.show(numero()) ++ " com chamadas paralelas")
    u: Unit <- IO.print(U32.show(pow2(U32.to_nat(numero()))))

    u: Unit <- IO.print("Calculando 2^" ++ U32.show(numero()) ++ " com chamadas sequenciais")
    u: Unit <- IO.print(U32.show(pow2_seq(U32.to_nat(numero()))))

    IO.print("fim")
