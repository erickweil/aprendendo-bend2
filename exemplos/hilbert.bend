import Base
import ./../utils/io.bend as IOU
import ./../utils/math.bend as M

# CURVA DE HILBERT, desenhada no terminal por uma "tartaruga" que segue o
# L-system  A -> +BF-AFA-FB+   B -> -AF+BFB+FA-  (F anda, + e - viram).
#
# Mostra um percurso GENÉRICO com callback: `hilbert(~S, ~f, n, acc)` visita
# cada posição da curva chamando `f(acc, posição, chegada, saída)`. O
# acumulador `S` é um `Type`, então pode ser um Array (aqui, a tela de
# caracteres). `hilbert_detalhe.bend` reusa o mesmo percurso para comprimir
# imagens.
#
#   bend hilbert.bend -o ../bin/hilbert && ../bin/hilbert [profundidade=3]

# -------------------------------------------------
# Tipos, Direção e Posição 2D
# -------------------------------------------------

type Dir is Data:
  Norte{}
  Leste{}
  Sul{}
  Oeste{}

# vira à direita (-)
def Dir.horario(dir: Dir) -> Dir:
  match dir:
    case Norte{}:
      Leste{}
    case Leste{}:
      Sul{}
    case Sul{}:
      Oeste{}
    case Oeste{}:
      Norte{}

# vira à esquerda (+)
def Dir.anti_horario(dir: Dir) -> Dir:
  match dir:
    case Norte{}:
      Oeste{}
    case Leste{}:
      Norte{}
    case Sul{}:
      Leste{}
    case Oeste{}:
      Sul{}

type Vec2 is Data:
  Vec2{x: U32, y: U32}

# anda um passo (F)
def Vec2.andar(vec: Vec2, dir: Dir) -> Vec2:
  Vec2{x, y} = vec
  match dir:
    case Norte{}:
      Vec2{x, (y + 1 : U32)}
    case Leste{}:
      Vec2{(x + 1 : U32), y}
    case Sul{}:
      Vec2{x, (y - 1 : U32)}
    case Oeste{}:
      Vec2{(x - 1 : U32), y}

def Vec2.index(vec: Vec2, largura: U32) -> U32:
  Vec2{x, y} = vec
  (y * largura + x : U32)

# -------------------------------------------------
# Lógica iteração percorrendo a curva de Hilbert
# -------------------------------------------------

type Tartaruga<-S: Type> is Type:
  Tartaruga{pos: Vec2, dir: Dir, chegada: Dir, acc: S}

def esquerda(-S: Type, t: Tartaruga<S>) -> Tartaruga<S>:
  Tartaruga{pos, dir, chegada, acc} = t
  Tartaruga{pos, Dir.anti_horario(dir), chegada, acc}

def direita(-S: Type, t: Tartaruga<S>) -> Tartaruga<S>:
  Tartaruga{pos, dir, chegada, acc} = t
  Tartaruga{pos, Dir.horario(dir), chegada, acc}

def frente(~S: Type, ~f: S -> Vec2 -> Dir -> Dir -> S, t: Tartaruga<S>) -> Tartaruga<S>:
  Tartaruga{+pos, +dir, chegada, acc} = t
  Tartaruga{Vec2.andar(pos, dir), dir, dir, f(acc, pos, chegada, dir)}

# As regras A e B se chamam mutuamente, e Bend não tem recursão mútua: vira
# UMA função, com um parâmetro (`a_lado`) que diz qual regra aplicar.
def iter(~S: Type, ~f: S -> Vec2 -> Dir -> Dir -> S, +n: Nat, a_lado: Bool, t: Tartaruga<S>) -> Tartaruga<S>:
  match n:
    case 0n:
      t
    case 1n+p:
      match a_lado:
        # ITER A -> +BF-AFA-FB+
        case True{}:
          t = esquerda(S, t)
          t = iter(~S, ~f, p, False{}, t)
          t = frente(~S, ~f, t)
          t = direita(S, t)
          t = iter(~S, ~f, p, True{}, t)
          t = frente(~S, ~f, t)
          t = iter(~S, ~f, p, True{}, t)
          t = direita(S, t)
          t = frente(~S, ~f, t)
          t = iter(~S, ~f, p, False{}, t)
          t = esquerda(S, t)
          t
        # ITER B -> -AF+BFB+FA-
        case False{}:
          t = direita(S, t)
          t = iter(~S, ~f, p, True{}, t)
          t = frente(~S, ~f, t)
          t = esquerda(S, t)
          t = iter(~S, ~f, p, False{}, t)
          t = frente(~S, ~f, t)
          t = iter(~S, ~f, p, False{}, t)
          t = esquerda(S, t)
          t = frente(~S, ~f, t)
          t = iter(~S, ~f, p, True{}, t)
          t = direita(S, t)
          t

# Consome o estado final da tartaruga, chamando a callback para a última posição
def hilbert.fim(~S: Type, ~f: S -> Vec2 -> Dir -> Dir -> S, t: Tartaruga<S>) -> S:
  Tartaruga{pos, dir, chegada, acc} = t
  f(acc, pos, chegada, dir)

# Percorre a curva inteira e devolve o acumulador no final
def hilbert(~S: Type, ~f: S -> Vec2 -> Dir -> Dir -> S, n: Nat, acc: S) -> S:
  tart : Tartaruga<S> = Tartaruga{Vec2{0, 0}, Leste{}, Leste{}, acc}
  tart = iter(~S, ~f, n, True{}, tart)
  hilbert.fim(~S, ~f, tart)

# -------------------------------------------------
# Lógica desenho da curva de Hilbert
# -------------------------------------------------

def dir_to_char(last: Dir, dir: Dir) -> Char:
  match last dir:
    case Leste{} Leste{}: '─'
    case Oeste{} Oeste{}: '─'

    case Norte{} Norte{}: '│'
    case Sul{} Sul{}:     '│'
    
    case Norte{} Leste{}: '┌'
    case Oeste{} Sul{}:   '┌'
    
    case Norte{} Oeste{}: '┐'
    case Leste{} Sul{}:   '┐'

    case Sul{} Leste{}:   '└'
    case Oeste{} Norte{}: '└'

    case Sul{} Oeste{}:   '┘'
    case Leste{} Norte{}: '┘'
    
    case _ _:             '?'

# A tela: 2 caracteres por posição (o conector à esquerda e a curva), com
# y = 0 embaixo. O conector da coluna 0 cai na última posição da linha de
# cima (o índice dá a volta), e ali vai o '\n': a grade inteira já é o texto.
type Tela is Type:
  Tela{grade: Array<Char>, largura: U32}

def conector(x: U32, chegada: Dir, dir: Dir) -> Char:
  match x:
    case 0: '\n'
    case _:
      match chegada dir:
        case Leste{} _: '─'
        case _ Oeste{}: '─'
        case _ _: ' '

# A callback: recebe e devolve o acumulador. Um template exige a assinatura
# exata (sem `+`), então os valores reusados são religados com `+x = x`.
def desenha(t: Tela, pos: Vec2, chegada: Dir, dir: Dir) -> Tela:
  Tela{grade, +largura} = t
  Vec2{+x, +y} = pos
  +chegada = chegada
  +dir = dir
  +i = Vec2.index(Vec2{(x * 2 : U32), (largura - y - 1 : U32)}, (largura * 2 : U32))
  grade = Array.set(Char, grade, (i - 1 : U32), conector(x, chegada, dir))
  Tela{Array.set(Char, grade, i, dir_to_char(chegada, dir)), largura}

# O texto da grade, lido do fim para o começo (assim cada caractere entra na
# frente com SCon, sem inverter no final)
def texto(k: Nat, r: Array<Char> & Char, +i: U32, acc: String) -> String:
  match k:
    case 0n:
      (g, c) = r
      SCon{c, acc}
    case 1n+p:
      (g, c) = r
      texto(p, Array.get(Char, g, (i - 1 : U32)), (i - 1 : U32), SCon{c, acc})

def Tela.show(t: Tela) -> String:
  Tela{grade, +largura} = t
  +fim = (2 * largura * largura - 1 : U32)
  texto(U32.to_nat(fim), Array.get(Char, grade, fim), fim, "")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +prof : U32 = U32.min(IOU.num_at(IOU.numbers(args), 0n, 3), 12)
    +largura : U32 = U32.shln(1, U32.to_nat(prof))
    tela : Tela = Tela{Array.new(Char, M.log2_ceil((2 * largura * largura : U32)), ' '), largura}
    IO.write(Tela.show(hilbert(~Tela, ~desenha, U32.to_nat(prof), tela)))
