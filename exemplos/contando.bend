import Base

# Função recursiva que usa IO para imprimir conforme vai contando
# O combustivel Nat vai decrescendo a cada chamada, para respeitar a garantia de que a função irá parar eventualmente
# Já o contador U32 é usado para exibir o número atual e fazer a contagem de fato
def contar(+combustivel: Nat, +contador: U32) -> IO(Unit):
  match combustivel:
    # Caso base: imprime e para
    case 0n:
      IO.print(U32.show(contador))
    case 1n+p:
      # def IO.bind(-A: Type, -B: Type, m: IO(A), f: A -> IO(B)) -> IO(B):
      # f é um lambda que retorna a próxima sequência de ações
      IO.bind(Unit, Unit, 
        IO.print(U32.show(contador)),        # 1. Ação atual: imprime o contador
        u => contar(p, (contador + 1 : U32)) # 2. Próxima ação: chama contar recursivamente
      )
  
def limite_padrao() -> U32:
  10

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
  limite = get_arg_u32(args, limite_padrao())
  contar(U32.to_nat(limite), 0)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)