import Base
import ./../utils/io.bend as IOUtils

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

def split.push(partes: List<String>, is_sep: Bool, c: Char) -> List<String>:
  match partes is_sep:
    # Primeiro push vai criar
    case Nil{} False{}:
      Con{SCon{c, SNil{}}, Nil{}}
    # Adiciona o caractere à string
    case Con{h, t} False{}:
      Con{SCon{c, h}, t}
    # Se é separador, cria uma nova string vazia
    case partes True{}:
      Con{SNil{}, partes}

# Recursivo primeiro, reconstrói na volta, para manter ordem
def split(+s: String, +sep: Char) -> List<String>:
  match s:
    case SNil{}:
      Con{SNil{}, Nil{}}
    case SCon{c, t}:
      split.push(split(t, sep), Char.eq(c, sep), c)

def show_list(list: List<String>) -> String:
  match list:
    case Nil{}:
      ""
    case Con{h, Nil{}}:
      h
    case Con{h, t}:
      h ++ ", " ++ show_list(t)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +txt : String = IOUtils.pop_or(&1, String, args, "Subi no Ônibus Arara em Roma")
    splitted : List<String> = split(txt, Chr{32})
    u : Unit <- IO.print("frase:     " ++ txt)
    u : Unit <- IO.print("separada:  " ++ show_list(splitted))
    u : Unit <- IO.print("invertida: " ++ inverter(txt, ""))
    u : Unit <- IO.print("tamanho:   " ++ U32.show(tamanho(txt)))
    
    IO.print("")