import Base
import ./../utils/io.bend as IOUtils
import ./../utils/math.bend as M

# -------------------------------------------------
# Tipos, Direção e Posição 2D
# -------------------------------------------------

type Dir is Data:
  Norte{}
  Leste{}
  Sul{}
  Oeste{}

# -
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

# +
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

def Dir.is_eq(a: Dir, b: Dir) -> Bool:
  match a, b:
    case Norte{}, Norte{}:
      True{}
    case Leste{}, Leste{}:
      True{}
    case Sul{}, Sul{}:
      True{}
    case Oeste{}, Oeste{}:
      True{}
    case _ _:
      False{}

type Vec2 is Data:
  Vec2{x: U32, y: U32}

# F
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

# iter_a e iter_b se chamam mutuamente, mas no Bend2 não dá para fazer (sem usar @unsafe), então por isso um função só
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

type CallbackData is Type:
  CallbackData{grade: Array<Char>, grade_len: U32, largura: U32}

def callback.conector(x: U32, chegada: Dir, dir: Dir) -> Char:
  match x:
    # Se é a primeira coluna, deve ligar com \n (-1 dá a volta e coloca o \n no último índice)
    case 0: '\n'
    case _:
      match chegada dir:
        # Se deve ligar com o conector da esquerda
        case Leste{} _: '─'
        case _ Oeste{}: '─'
        # Se não deve ligar com o conector da esquerda
        case _ _:       ' '

def callback(data: CallbackData, pos: Vec2, chegada: Dir, dir: Dir) -> CallbackData:
  CallbackData{grade, grade_len, +largura} = data
  Vec2{+x, +y} = pos
  +chegada = chegada
  +dir = dir

  +index = Vec2.index(Vec2{(x * 2 : U32), (largura - y - 1 : U32)}, (largura * 2 : U32))
  grade = Array.set(Char, grade, (index - 1 : U32), callback.conector(x, chegada, dir))
  grade = Array.set(Char, grade, index, dir_to_char(chegada, dir))
  
  CallbackData{grade, grade_len, largura}

def print_linhas.monta(n: Nat, r: Array<Char> & Char, +i: U32, acc: String) -> Array<Char> & String:
  match n:
    case 0n:
      (grade, c) = r
      (grade, SCon{c, acc})
    case 1n+p:
      (grade, c) = r
      +prev = (i - 1 : U32)
      print_linhas.monta(p, Array.get(Char, grade, prev), prev, SCon{c, acc})

def print_linhas(n: Nat, buffer: Array<Char> & String, +passo: U32, +fim: U32) -> IO(Unit):
  match n:
    case 0n:
      (grade, s) = buffer
      IO.write(s)
    case 1n+p:
      (grade, s) = buffer
      +novo_fim = (fim + passo : U32)
      do IO<Unit>:
        u : Unit <- IO.write(s)
        print_linhas(p, 
          print_linhas.monta(U32.to_nat((passo - 1 : U32)), Array.get(Char, grade, novo_fim), novo_fim, SNil{}), 
          passo, 
          novo_fim
        )

def callback.print(data: CallbackData) -> IO(Unit):
  CallbackData{grade, grade_len, +largura} = data
  +passo = (largura * 2 : U32)
  +fim = (passo - 1 : U32)
  print_linhas(
    U32.to_nat((largura - 1 : U32)), 
    print_linhas.monta(U32.to_nat(fim), Array.get(Char, grade, fim), fim, SNil{}),
    passo,
    fim
  )

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +profundidade : U32 = IOUtils.num_at(IOUtils.numbers(args), 0n, 3)
    +largura : U32 = U32.shln(1, U32.to_nat(profundidade))
    +grade_len : U32 = ((largura * 2 : U32) * largura : U32)
    grade : Array<Char> = Array.new(Char, M.log2_ceil(grade_len), '!')

    callback.print(
      hilbert(~CallbackData, ~callback, U32.to_nat(profundidade), CallbackData{grade, grade_len, largura})
    )