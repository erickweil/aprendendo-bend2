import Base

def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

# Uma String é uma lista encadeada de caracteres apontando para os próximos da frente
# type Char is Data:
#   Chr{code: U32}
#
# type String is Data:
#   SNil{}
#   SCon{head: Char, tail: String}
#
# Veja o que é um 'ola'
#          o              l              a
# SCon{Chr{111}, SCon{Chr{108}, SCon{Chr{97}, SNil{}}}}
# Portanto pode ser decomposto em primeiro caractere e resto
# E verificar o tamanho é um processo de atravessar todos os nós da lista encadeada
def tamanho(s: String) -> U32:
  match s:
    case SNil{}:
      0
    case SCon{head, tail}:
      (tamanho(tail) + 1 : U32)

# Inverter uma string, extrai cada caractere e junta ao contrário
def inverter(+s: String, acc: String) -> String:
  match s:
    # Caso base, quando não há mais caracteres, retorna o acumulador
    case SNil{}:
      acc
    # Caso recursivo, extrai o primeiro caractere e chama a função recursivamente com o resto
    case SCon{head, tail}:
      inverter(tail, SCon{head, acc})

def frase() -> String:
  "Subi no Ônibus Arara em Roma"

def main() -> IO(Unit):
  +txt = frase()
  do IO<Unit>:
    u : Unit <- IO.print("frase:     " ++ txt)
    u : Unit <- IO.print("invertida: " ++ inverter(txt, ""))
    u : Unit <- IO.print("tamanho:   " ++ U32.show(tamanho(txt)))
    
    IO.print("")