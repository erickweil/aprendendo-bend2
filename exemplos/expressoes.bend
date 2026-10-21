import Base
import ./../utils/io.bend as IOU

# CALCULADORA EM NOTAÇÃO POLONESA REVERSA (RPN): "3 4 + 2 *" é (3 + 4) * 2.
# Mostra tipos com vários construtores, `match` sobre String, uma pilha
# feita com lista e a avaliação de uma árvore EM PARALELO.

type Op is Data:
  Soma{}
  Sub{}
  Mul{}
  Div{}

type Token is Data:
  Num{valor: U32}
  Oper{op: Op}

type Expr is Data:
  Valor{valor: U32}
  Bin{op: Op, esq: Expr, dir: Expr}

def Op.show(op: Op) -> String:
  match op:
    case Soma{}: "+"
    case Sub{}: "-"
    case Mul{}: "*"
    case Div{}: "/"

def Expr.show(e: Expr) -> String:
  match e:
    case Valor{v}: U32.show(v)
    case Bin{op, a, b}: "(" ++ Expr.show(a) ++ " " ++ Op.show(op) ++ " " ++ Expr.show(b) ++ ")"

# --- 1. texto -> tokens ---

# Um `match` compara Strings inteiras com literais
def token(s: String) -> Maybe<&2, Token>:
  match s:
    case "+": Some{Oper{Soma{}}}
    case "-": Some{Oper{Sub{}}}
    case "*": Some{Oper{Mul{}}}
    case "/": Some{Oper{Div{}}}
    case outro: Maybe.map(&2, U32, Token, (v => Num{v}), U32.read(outro))

# Auxiliar não recursivo: põe o token na frente, se ele existir
def poe(m: Maybe<&2, Token>, resto: List<&2, Token>) -> List<&2, Token>:
  match m:
    case None{}: resto
    case Some{t}: t <> resto

def tokens(palavras: List<&2, String>) -> List<&2, Token>:
  match palavras:
    case Nil{}: []
    case p <> resto: poe(token(p), tokens(resto))

# --- 2. tokens -> árvore, com uma pilha ---

# Um número entra na pilha; um operador tira dois e põe a combinação.
# A assinatura `pilha -> token -> pilha` é a que `List.foldl` espera. Os
# `match` seguem a ordem dos parâmetros (`pilha` antes de `t`), então os
# dois são abertos juntos, num `match` múltiplo.
def empilha(pilha: List<&2, Expr>, t: Token) -> List<&2, Expr>:
  match pilha t:
    case p Num{v}: Valor{v} <> p
    case b <> a <> resto Oper{op}: Bin{op, a, b} <> resto
    case p Oper{op}: p

# --- 3. avaliar, em paralelo ---

def aplica(op: Op, +a: U32, +b: U32) -> U32:
  match op:
    case Soma{}: (a + b : U32)
    case Sub{}: (a - b : U32)
    case Mul{}: (a * b : U32)
    case Div{}: (a / b : U32)

# Os dois lados de um nó são independentes: `a b = f(x) f(y)` os avalia ao
# mesmo tempo (em expressões pequenas não compensa; é só para mostrar).
def avaliar(e: Expr) -> U32:
  match e:
    case Valor{v}: v
    case Bin{op, esq, dir}:
      a b = avaliar(esq) avaliar(dir)
      aplica(op, a, b)

def resultado(pilha: List<&2, Expr>) -> String:
  match pilha:
    case [+e]: Expr.show(e) ++ " = " ++ U32.show(avaliar(e))
    case _: "expressão inválida"

def nao_vazia(s: String) -> Bool:
  Bool.not(String.is_empty(s))

# Uso: expressoes "3 4 + 2 *"      (ou cada token num argumento)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    +texto : String = Bool.pick(String, List.is_empty(&2, String, ts), "3 4 + 10 2 - *", String.join(ts, " "))
    palavras : List<&2, String> = List.filter(~String, ~nao_vazia, String.split(texto, ' '))
    IO.print(texto)
    IO.print(resultado(List.foldl(~&2, ~Token, ~List<&2, Expr>, ~empilha, tokens(palavras), [])))
