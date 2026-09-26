# Todo código deve importar Base
import Base

# Funções seguem a estrutura:
#
#   def NOME(A: TIPO, B: TIPO, ...) -> RETORNO:
#     corpo
#
# O corpo é UMA expressão (a última linha), e ela é o resultado. Uma função
# só pode chamar a si mesma e as funções definidas ANTES dela no arquivo.

# Operadores precisam do tipo em volta, no formato (EXPRESSÃO : TIPO)
def soma(a: U32, b: U32) -> U32:
  (a + b : U32)

def media(a: U32, b: U32) -> U32:
  (soma(a, b) / 2 : U32)

# O maior entre a e b. Os dois são usados duas vezes (na comparação e na
# escolha), por isso o `+`. `Bool.pick(T, condição, se_sim, se_não)` escolhe
# um dos dois valores (a Base também tem `U32.max`).
def maior(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a > b : U32), a, b)

# A nota do semestre: a média das provas, ou a recuperação se for maior
def semestre(p1: U32, p2: U32, rec: U32) -> U32:
  maior(media(p1, p2), rec)

def situacao(+nota: U32) -> String:
  U32.show(nota) ++ ": " ++ Bool.pick(String, (nota >= 60 : U32), "passou", "reprovou")

def main() -> IO(Unit):
  # `nome : Tipo = valor` dá nome a um valor já com o tipo (um literal
  # sozinho não sabe se é U32, F32...)
  sem1 : U32 = semestre(40, 70, 80)
  sem2 : U32 = semestre(80, 40, 0)
  IO.print("média anual " ++ situacao(media(sem1, sem2)))
