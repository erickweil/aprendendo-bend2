import Base
import ./../utils/io.bend as IOU

# Uma String é uma lista encadeada de caracteres:
#
#   type Char is Data:
#     Chr{code: U32}
#
#   type String is Data:
#     SNil{}
#     SCon{head: Char, tail: String}
#
# "ola" é SCon{Chr{111}, SCon{Chr{108}, SCon{Chr{97}, SNil{}}}}: pode ser
# aberta em primeiro caractere e resto, e medir o tamanho é percorrê-la.

# Percorrendo à mão (a Base já tem `String.length`, que devolve um Nat)
def tamanho(s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{c, resto}: (1 + tamanho(resto) : U32)

# Um `match` compara Char com literais ('a'); `_` pega o resto
def vogal(c: Char) -> Bool:
  match c:
    case 'a': True{}
    case 'e': True{}
    case 'i': True{}
    case 'o': True{}
    case 'u': True{}
    case _: False{}

def vogais(s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{c, resto}: (Bool.to_u32(vogal(Char.to_lower(c))) + vogais(resto) : U32)

def nao_vazia(s: String) -> Bool:
  Bool.not(String.is_empty(s))

def aspas(s: String) -> String:
  "\"" ++ s ++ "\""

def mostrar(xs: List<&2, String>) -> String:
  List.show(~&2, ~String, ~aspas, xs)

# Uso: strings [texto...]   (as palavras são juntadas com espaço)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    +txt : String = Bool.pick(String, List.is_empty(&2, String, ts), "Subi no onibus em Marrocos", String.join(ts, " "))
    +palavras : List<&2, String> = List.filter(~String, ~nao_vazia, String.split(txt, ' '))
    IO.print("frase:      " ++ txt)
    IO.print("tamanho:    " ++ U32.show(tamanho(txt)) ++ " (String.length: " ++ Nat.show(String.length(txt)) ++ ")")
    IO.print("vogais:     " ++ U32.show(vogais(txt)))
    IO.print("palavras:   " ++ mostrar(palavras))
    IO.print("com |:      " ++ String.join(palavras, " | "))
    IO.print("invertida:  " ++ String.reverse(txt))
    IO.print("maiúsculas: " ++ String.to_upper(txt))
    IO.print("tem \"em\"?   " ++ Bool.show(String.contains(txt, "em")))
    IO.print("1ª letra:   " ++ Maybe.show(~&2, ~Char, ~Char.show, String.get(txt, 0n)))
