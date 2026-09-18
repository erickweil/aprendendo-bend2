import Base
import arvore.bend as A

def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

def powerOfTwo(n: Nat, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      powerOfTwo(p, (acc + acc : U32))

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

type Estado is Data:
  EstadoFim{}
  Estado{pos: Vec2, dir: Dir, chegada: Dir, acc: Estado}

def esquerda(estado: Estado) -> Estado:
    match estado:
    case EstadoFim{}:
      EstadoFim{}
    case Estado{pos, dir, chegada, acc}:
      Estado{pos, Dir.anti_horario(dir), chegada, acc}

def direita(estado: Estado) -> Estado:
    match estado:
    case EstadoFim{}:
      EstadoFim{}
    case Estado{pos, dir, chegada, acc}:
      Estado{pos, Dir.horario(dir), chegada, acc}

def frente(+estado: Estado) -> Estado:
    match estado:
    case EstadoFim{}:
      EstadoFim{}
    case Estado{pos, dir, chegada, acc}:
      Estado{Vec2.andar(pos, dir), dir, dir, estado}

# iter_a e iter_b se chamam mutuamente, mas no Bend2 não dá para fazer, então por isso um função só
def iter(+n: Nat, a_lado: Bool, estado: Estado) -> Estado:
  match n:
    case 0n:
      estado
    case 1n+p:
      match a_lado:
        # ITER A -> +BF-AFA-FB+
        case True{}:
          estado = esquerda(estado)
          estado = iter(p, False{}, estado)
          estado = frente(estado)
          estado = direita(estado)
          estado = iter(p, True{}, estado)
          estado = frente(estado)
          estado = iter(p, True{}, estado)
          estado = direita(estado)
          estado = frente(estado)
          estado = iter(p, False{}, estado)
          estado = esquerda(estado)
          estado
        # ITER B -> -AF+BFB+FA-
        case False{}:
          estado = direita(estado)
          estado = iter(p, True{}, estado)
          estado = frente(estado)
          estado = esquerda(estado)
          estado = iter(p, False{}, estado)
          estado = frente(estado)
          estado = iter(p, False{}, estado)
          estado = esquerda(estado)
          estado = frente(estado)
          estado = iter(p, True{}, estado)
          estado = direita(estado)
          estado

def Estado.inicial() -> Estado:
  Estado{Vec2{0, 0}, Leste{}, Leste{}, EstadoFim{}}

def build_tree.char(last: Dir, dir: Dir) -> String:
  match last, dir:
    case Leste{}, Leste{}:
      "─"
    case Oeste{}, Oeste{}:
      "─"
    case Norte{}, Norte{}:
      "│"
    case Sul{}, Sul{}:
      "│"
    
    case Norte{}, Leste{}:
      "┌"
    case Oeste{}, Sul{}:
      "┌"
    
    case Norte{}, Oeste{}:
      "┐"
    case Leste{}, Sul{}:
      "┐"

    case Sul{}, Leste{}:
      "└"
    case Oeste{}, Norte{}:
      "└"

    case Sul{}, Oeste{}:
      "┘"
    case Leste{}, Norte{}:
      "┘" 
    
    case _ _:
      "?"

type Vec2Char is Data:
  Vec2Char{pos: Vec2, char: String, liga_esquerda: Bool}

def Vec2Char.cmp(a: Vec2Char, b: Vec2Char) -> Cmp:
  match a b:
    case Vec2Char{Vec2{+x1, +y1}, _, _} Vec2Char{Vec2{+x2, +y2}, _, _}:
      # compara y, mas se é igual compara x
      pick(Cmp, U32.is_eq(y1, y2),
        pick(Cmp, U32.is_eq(x1, x2),
          EQ{},
          pick(Cmp, (x1 < x2 : U32),
            LT{},
            GT{}
          )
        ),
        pick(Cmp, (y1 < y2 : U32),
          LT{},
          GT{}
        )
      )

def build_tree(estado: Estado) -> A.Arvore<Vec2Char>:
  match estado:
    case EstadoFim{}:
      A.Vazia{}
    case Estado{pos, +dir, +chegada, acc}:
      char = build_tree.char(chegada, dir)
      liga_esquerda = Dir.is_eq(chegada, Leste{}) || Dir.is_eq(dir, Oeste{})
      A.inserir(~Vec2Char, ~Vec2Char.cmp, 
        build_tree(acc), 
        Vec2Char{pos, char, liga_esquerda}
      )

# liga_esquerda indica se deve ter o traço conectando ou não, para ficar quadrado no terminal
def draw.tree.char(+valor: Maybe<&2, Vec2Char>, +line: String) -> String:
  match valor:
    case None{}:
      line ++ "?"
    case Some{Vec2Char{_, char, liga_esquerda}}:
      match line:
        case "":
          char
        case _:
          pick(String, liga_esquerda, line ++ "─" ++ char, line ++ " " ++ char)

def draw.tree.line(+n: Nat, +x: U32, +y: U32, +tree: A.Arvore<Vec2Char>, line: String) -> String:
  match n:
    case 0n:
      line
    case 1n+p:
      line = draw.tree.line(p, (x - 1 : U32), y, tree, line)
      draw.tree.char(A.buscar(~Vec2Char, ~Vec2Char.cmp, tree, Vec2Char{Vec2{(x - 1 : U32),(y - 1 : U32)}, "", False{}}), line)

# Trafega y de baixo para cima, e x da esquerda para direita
def draw.tree(+n: Nat, +y: U32, +largura: U32, +tree: A.Arvore<Vec2Char>, result: String) -> String:
  match n:
    case 0n:
      result
    case 1n+p:
      line = draw.tree.line(U32.to_nat(largura), largura, y, tree, "")
      draw.tree(p, (y - 1 : U32), largura, tree, result ++ line ++ "\n")

def draw.fin(profundidade: U32, tree: A.Arvore<Vec2Char>) -> String:
  +largura = powerOfTwo(U32.to_nat(profundidade), 1)
  draw.tree(U32.to_nat(largura), largura, largura, tree, "")

def profundidade() -> U32:
  3

def parse_u32(m: Maybe<&2, U32>, default: U32) -> U32:
  match m:
    case None{}: default
    case Some{val}: val

def get_arg_u32(args: List<String>, default: U32) -> U32:
  match args:
    case Nil{}: default
    case Con{first, rest}:
      parse_u32(U32.read(first), default)

def run(args: List<String>) -> IO(Unit):
  +prof = get_arg_u32(args, profundidade())
  estado = iter(U32.to_nat(prof), True{}, Estado.inicial())
  IO.write(draw.fin(prof, build_tree(estado)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)