# Todo código deve importar Base
import Base

# Valor a ser usado no exemplo (padrão se não informado via CLI)
def valor() -> U32:
  1
  
# Função auxiliar padrão para retornar o valor baseado em um teste lógico
# é necessária pois o match só pode ser utilizado em valores recebido em parâmetros,
# não pode em bindings locais ou valores computados
def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

# Função que retorna se o valor de um Nat é zero ou maior que zero
# O match é uma forma de executar apenas um caminho do código, 
# Só pode ser usado apenas com parâmetros ou valores extraídos deles, nunca valores computados ou chamada de função
def descrever(v: Nat) -> String:
  match v:
    case 0n:
      "zero"
    case 1n+p:
      "maior que zero"

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
  +valor_u32 = get_arg_u32(args, valor())
  +valor_nat = U32.to_nat(valor_u32)
  
  # Com o número Nat, é possível criar uma função que usa o match diretamente
  msg = descrever(valor_nat) ++ "\n"

  # Mas também existe o Nat.cmp que permite comparar dois Nat e retorna um Cmp
  # Usando então o Cmp.is_gt que retorna um Bool apenas caso seja GT{}
  msg = msg ++ pick(String, Cmp.is_gt(Nat.cmp(valor_nat, 0n)), "Maior que Zero", "Zero") ++ "\n"

  # Com o número U32 não é útil usar match diretamente (é decomposto em 32 bits, não ajuda comparação)
  # Aqui faz o teste lógica com o operador > e então usa pick para fazer match com o Bool
  msg = msg ++ pick(String, (valor_u32 > 0 : U32), "Maior que Zero", "Zero")

  IO.print(msg)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)

