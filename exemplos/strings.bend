import Base

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


# Char é Chr{code: U32}, então comparar caractere é comparar número
def Char.eq(a: Char, b: Char) -> Bool:
  match a b:
    case Chr{x} Chr{y}:
      U32.is_eq(x, y)

def split.push(c: Char, partes: List<&2, String>) -> List<&2, String>:
  match partes:
    case Nil{}:
      Con{SCon{c, SNil{}}, Nil{}}
    case Con{h, t}:
      Con{SCon{c, h}, t}

# Recursivo primeiro, reconstrói na volta, para manter ordem
def split(+s: String, +sep: Char) -> List<&2, String>:
  match s:
    case SNil{}:
      Con{SNil{}, Nil{}}
    case SCon{c, t}:
      pick(List<&2, String>, Char.eq(c, sep),
        Con{SNil{}, split(t, sep)},
        split.push(c, split(t, sep)))

def frase() -> String:
  "Subi no Ônibus Arara em Roma"

def main() -> IO(Unit):
  +txt = frase()
  do IO<Unit>:
    u : Unit <- IO.print("frase:     " ++ txt)
    u : Unit <- IO.print("invertida: " ++ inverter(txt, ""))
    u : Unit <- IO.print("tamanho:   " ++ U32.show(tamanho(txt)))
    
    IO.print("")