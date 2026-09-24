import Base
import ./../utils/io.bend as IOU

# Uma função:
#   def NOME(PARAM: TIPO, ...) -> RETORNO:
#     corpo (o valor da última expressão é o retorno)
#
# Uma função só enxerga as que foram definidas ACIMA dela no arquivo.

def soma(a: U32, b: U32) -> U32:
  (a + b : U32)

def media(a: U32, b: U32) -> U32:
  (soma(a, b) / 2 : U32)

# Um parâmetro usado mais de uma vez precisa de `+`. `Bool.pick` escolhe
# entre dois valores (a Base já tem `U32.max`, que faz exatamente isto).
def maior(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a > b : U32), a, b)

# A nota do semestre é a média das provas, ou a recuperação se for maior
def semestre(p1: U32, p2: U32, rec: U32) -> U32:
  maior(media(p1, p2), rec)

def situacao(+anual: U32) -> String:
  Bool.pick(String, (anual >= 60 : U32), "Passou", "Reprovou")

# Uso: funcoes [p1 p2 rec1 p3 p4 rec2]
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +s1 : U32 = semestre(IOU.num_at(ns, 0n, 40), IOU.num_at(ns, 1n, 70), IOU.num_at(ns, 2n, 80))
    +s2 : U32 = semestre(IOU.num_at(ns, 3n, 80), IOU.num_at(ns, 4n, 40), IOU.num_at(ns, 5n, 0))
    +anual : U32 = media(s1, s2)
    IO.print("1º semestre: " ++ U32.show(s1) ++ ", 2º semestre: " ++ U32.show(s2))
    IO.print("Média anual " ++ U32.show(anual) ++ ": " ++ situacao(anual))
