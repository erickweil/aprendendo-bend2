# Todo código deve importar Base
import Base

# Função para retornar o valor inicial
# U32 é um valor inteiro sem sinal com 32 bits.
def valor_u32() -> U32:
  20
  
# Já o Nat (Natural) é um tipo diferente de número,
# Usado para contagens e outras situações que é necessário ter certeza que o programa irá parar eventualmente
def valor_nat() -> Nat:
  7n

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
  # Por padrão, é como se os valores fossem sem Clone e Copy do Rust, mas aqui a variável decide isso
  # Se você quer poder reusar uma variável mais de uma vez, precisa marcar com +, ou irá dar erro 'consumed more than once'
  +quanto = get_arg_u32(args, valor_u32())

  # então em seguida podemos usar mais de uma vez a variável
  # Redeclarar é como no Rust, estamos criando uma NOVA variável e vira shadow da anterior
  quanto = (quanto + quanto + quanto : U32)
  
  # Fazer isso denovo daria erro pois a variável quanto anterior foi criada sem o +
  # quanto = (quanto + quanto : U32);
  
  # Não é possível somar valores U32 com Nat, primeiro precisamos converter para Nat
  # E aqui a variável quanto foi redeclarada com OUTRO TIPO, o tipo Nat
  quanto = (U32.to_nat(quanto) + valor_nat() : Nat)

  IO.print(Nat.show(quanto))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)