import Base

def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

def List.pop(-A: Data, lista: List<&2, A>) -> Maybe<&2, A>:
  match lista:
    case Nil{}:
      None{}
    case Con{h, t}:
      Some{h}

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

# map_or do Option do Rust
def Maybe.map_or(-A: Data, -B: Data, maybe: Maybe<&2, A>, f: A -> B, default: B) -> B:
  match maybe:
    case None{}:
      default
    case Some{valor}:
      f(valor)

type Operador is Data:
  Soma{}
  Subtracao{}
  Multiplicacao{}
  Divisao{}

def Operador.show(+op: Operador) -> String:
  match op:
    case Soma{}:
      "+"
    case Subtracao{}:
      "-"
    case Multiplicacao{}:
      "*"
    case Divisao{}:
      "/"

type ParsedToken is Data:
  Numero{valor: U32}
  Operador{op: Operador}

def ParsedToken.is_operador(token: ParsedToken) -> Bool:
  match token:
    case Operador{op}:
      True{}
    case Numero{v}:
      False{}

type ArvoreExpr is Data:
  Valor{valor: U32}
  Expr{op: Operador, esquerda: ArvoreExpr, direita: ArvoreExpr}

def ArvoreExpr.show(+arvore: ArvoreExpr) -> String:
  match arvore:
    case Valor{valor}:
      U32.show(valor)
    case Expr{op, esquerda, direita}:
      "(" ++ ArvoreExpr.show(esquerda) ++ Operador.show(op) ++ ArvoreExpr.show(direita) ++ ")"


def ArvoreExpr.from_rpn.token(+token: ParsedToken, pilha: List<&2, ArvoreExpr>) -> List<&2, ArvoreExpr>:
  match token:
    case Numero{valor}:
      Con{Valor{valor}, pilha}
    case Operador{op}:
      # LIFO, então a direita vem primeiro
      match pilha:
        case Con{dir, Con{esq, resto}}:
          Con{Expr{op, esq, dir}, resto}
        case outro:
          outro

def ArvoreExpr.from_rpn.go(parsed: List<&2, ParsedToken>, pilha: List<&2, ArvoreExpr>) -> List<&2, ArvoreExpr>:
  match parsed:
    case Nil{}:
      pilha
    case Con{token, rest}:
      ArvoreExpr.from_rpn.go(rest, ArvoreExpr.from_rpn.token(token, pilha))

def ArvoreExpr.from_rpn(parsed: List<&2, ParsedToken>) -> Maybe<&2, ArvoreExpr>:
  List.pop(ArvoreExpr, ArvoreExpr.from_rpn.go(parsed, []))

def parse.token(+token: String) -> Maybe<&2, ParsedToken>:
  match token:
    case SNil{}:
      None{}
    case "+":
      Some{Operador{Soma{}}}
    case "-":
      Some{Operador{Subtracao{}}}
    case "*":
      Some{Operador{Multiplicacao{}}}
    case "/":
      Some{Operador{Divisao{}}}
    case outro:
      maybe_num = U32.read(outro)
      Maybe.map_or(U32, Maybe<&2, ParsedToken>, maybe_num, 
        valor => Some{Numero{valor}}, 
        None{}
      )

def parse(+tokens: List<&2, String>) -> List<&2, ParsedToken>:
  match tokens:
    case Nil{}:
      []
    case Con{token, rest}:
      +parsed_token = parse.token(token)
      Maybe.map_or(ParsedToken, List<&2, ParsedToken>, parsed_token, 
        t => Con{t, parse(rest)}, 
        parse(rest)
      )

def avaliar.op(+op: Operador, +esquerda: U32, +direita: U32) -> U32:
  match op:
    case Soma{}:
      (esquerda + direita : U32)
    case Subtracao{}:
      (esquerda - direita : U32)
    case Multiplicacao{}:
      (esquerda * direita : U32)
    case Divisao{}:
      (esquerda / direita : U32)

def avaliar(+arvore: ArvoreExpr) -> U32:
  match arvore:
    case Valor{valor}:
      valor
    case Expr{op, esquerda, direita}:
      +esquerda_valor = avaliar(esquerda)
      +direita_valor = avaliar(direita)
      avaliar.op(op, esquerda_valor, direita_valor)

# Expressão escrita em notação polonesa reversa (RPN)
def expressao() -> String:
  "5 9 + 2 * 3 +"

def main() -> IO(Unit):
  tokens = split(expressao(), ' ')
  parsed_tokens = parse(tokens)

  +arvore = ArvoreExpr.from_rpn(parsed_tokens)
  msg = Maybe.map_or(ArvoreExpr, String, arvore,
    a =>
      +a = a
      ArvoreExpr.show(a) ++ "\n" ++ U32.show(avaliar(a))
    ,
    "Erro ao construir árvore"
  )

  IO.print(msg)