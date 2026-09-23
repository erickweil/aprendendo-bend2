# Todo código deve importar Base
import Base

# Funções seguem estrutura:
# def NOME(A: TIPO, B: TIPO, ...) -> RETORNO:
#   ...
# Uma função só pode chamar a si mesma e funções que foram definidas antes dela
def valor(v: U32) -> U32:
  v
  
# Expressões precisam de anotação de tipo no formato ( EXPRESSAO : TIPO )
def soma(a: U32, b: U32) -> U32:
  (a + b : U32)
  
def media(a: U32, b: U32) -> U32:
  (soma(a,b) / 2 : U32)

# Utilizando a função pick, escolhe o maior valor entre a e b
def maior(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a > b : U32), a, b)
  
def main() -> IO(Unit):
  nota1 = valor(40)
  nota2 = valor(70)
  rec1 = valor(80)
  
  nota3 = valor(80)
  nota4 = valor(40)
  rec2 = valor(0)

  sem1 = maior(media(nota1, nota2), rec1)
  sem2 = maior(media(nota3, nota4), rec2)

  anual = media(sem1, sem2)
    
  IO.print(Bool.pick(String, (anual > 60 : U32), "Passou", "Reprovou"))