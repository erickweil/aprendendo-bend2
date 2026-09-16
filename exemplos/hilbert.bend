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

def Dir.show(dir: Dir) -> String:
  match dir:
    case Norte{}:
      "Norte"
    case Leste{}:
      "Leste"
    case Sul{}:
      "Sul"
    case Oeste{}:
      "Oeste"

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

type Vec2 is Data:
  Vec2{x: U32, y: U32}

def Vec2.from_nat(x: Nat, y: Nat) -> Vec2:
  Vec2{U32.from_nat(x), U32.from_nat(y)}

def Vec2.show(vec: Vec2) -> String:
  Vec2{x, y} = vec
  U32.show(x) ++ ", " ++ U32.show(y)

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
  Estado{pos: Vec2, dir: Dir, acc: Estado}

def esquerda(estado: Estado) -> Estado:
    match estado:
    case EstadoFim{}:
      EstadoFim{}
    case Estado{pos, dir, acc}:
      Estado{pos, Dir.anti_horario(dir), acc}

def direita(estado: Estado) -> Estado:
    match estado:
    case EstadoFim{}:
      EstadoFim{}
    case Estado{pos, dir, acc}:
      Estado{pos, Dir.horario(dir), acc}

def frente(+estado: Estado) -> Estado:
    match estado:
    case EstadoFim{}:
      EstadoFim{}
    case Estado{pos, dir, acc}:
      Estado{Vec2.andar(pos, dir), dir, estado}

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
  Estado{Vec2{0, 0}, Leste{}, EstadoFim{}}

def draw.char(last: Dir, dir: Dir) -> String:
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
  Vec2Char{pos: Vec2, char: String}

def Vec2Char.cmp(a: Vec2Char, b: Vec2Char) -> Cmp:
  match a b:
    case Vec2Char{Vec2{x1, y1}, _} Vec2Char{Vec2{x2, y2}, _}:
      +x1 = x1
      +x2 = x2
      +y1 = y1
      +y2 = y2
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

def draw.go(result: Dir & A.Arvore<Vec2Char>, +pos: Vec2, +dir: Dir) -> Dir & A.Arvore<Vec2Char>:
  (last, tree) = result
  +last = last
  tree = A.inserir(~Vec2Char, ~Vec2Char.cmp, tree, Vec2Char{pos, draw.char(last, dir)})
  (dir, tree)

def draw(estado: Estado, first: Dir) -> Dir & A.Arvore<Vec2Char>:
  match estado:
    case EstadoFim{}:
      (first, A.Vazia{})
    case Estado{pos, dir, acc}:
      result = draw(acc, first)
      draw.go(result, pos, dir)

def draw.tree.char(+valor: Maybe<&2, Vec2Char>, result: String & String) -> String & String:
  match valor:
    case None{}:
      (_, line) = result
      ("\n", line ++ "\n")
    case Some{Vec2Char{_, char}}:
      (prev_char, line) = result
      +prev_char = prev_char
      +line = line
      new_line = pick(String, String.eq(prev_char, "─") || String.eq(prev_char, "┌") || String.eq(prev_char, "└"),
        line ++ "─" ++ char,
        line ++ " " ++ char
      )
      (char, new_line)

def draw.tree.line(+x: Nat, +y: Nat, +tree: A.Arvore<Vec2Char>, result: String & String) -> String & String:
  match x:
    case 0n:
      (_, line) = result
      ("", line)
    case 1n+p:
      +pos = Vec2.from_nat((x - 1n : Nat), (y - 1n : Nat))
      result = draw.tree.line(p, y, tree, result)
      draw.tree.char(A.buscar(~Vec2Char, ~Vec2Char.cmp, tree, Vec2Char{pos, ""}), result)

# Trafega y de baixo para cima, e x da esquerda para direita
def draw.tree(+y: Nat, +x: Nat, +tree: A.Arvore<Vec2Char>, result: String & String) -> String & String:
  match y:
    case 0n:
      result
    case 1n+p:
      (prev_char, line) = result
      result = draw.tree.line(x, 1n+p, tree, ("", line))
      result = draw.tree.char(None{}, result)
      draw.tree(p, x, tree, result)

def draw.tree.fin(result: String & String) -> String:
  (_, line) = result
  line

def draw.fin(profundidade: U32, last: Dir & A.Arvore<Vec2Char>) -> String:
  (_, tree) = last
  +largura = powerOfTwo(U32.to_nat(profundidade), 1)
  draw.tree.fin(draw.tree(U32.to_nat(largura), U32.to_nat(largura), tree, ("", "")))

def profundidade() -> U32:
  4

def main() -> IO(Unit):
  estado = iter(U32.to_nat(profundidade()), True{}, Estado.inicial())
  IO.write(draw.fin(profundidade(), draw(estado, Leste{})))