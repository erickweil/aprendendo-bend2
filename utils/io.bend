import Base

# ================================================================
# ENTRADA E SAÍDA (io.bend)
# ================================================================
# ARGUMENTOS. `IO.args()` entrega `List<String>`, isto é `List<&1, String>`:
# uma lista AFIM, que só pode ser percorrida uma vez e não aceita `+`. Aqui ela
# é convertida de uma vez numa lista `Data` (`&2`), que pode ser consultada
# quantas vezes for preciso:
#
#   args : List<String> <- IO.args()
#   +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
#   +n : U32 = IOU.num_at(ns, 0n, 10)            # 1º argumento, ou 10
#
#   +ts : List<&2, String> = IOU.texts(args)
#   +caminho : String = IOU.text_at(ts, 1n, "entrada.bmp")
#   +raio : U32 = IOU.text_num_at(ts, 2n, 3)      # números e textos juntos
#
# TEMPO. `IO.now()` devolve milissegundos. O código puro só é calculado
# quando alguém precisa do valor, então para medir um cálculo IMPRIMA o
# resultado antes de ler o relógio de novo:
#
#   t0 : Nat <- IO.now()
#   IO.print(U32.show(resultado))
#   dt : String <- IOU.tempo_desde(t0)
#
# SEMENTE. `semente(s)` devolve `s`, ou um número aleatório do sistema se
# `s = 0` (uma syscall: use só uma vez, no `main`; veja utils/random.bend).

# ----------------------------------------------------------------
# ARGUMENTOS
# ----------------------------------------------------------------

# Todos os argumentos como números (`None` onde não for número)
def numbers(args: List<String>) -> List<&2, Maybe<&2, U32>>:
  match args:
    case Nil{}:
      Nil{}
    case Con{first, rest}:
      Con{U32.read(first), numbers(rest)}

# O k-ésimo número (a partir de 0), ou o padrão se faltar ou não for número
def num_at(l: List<&2, Maybe<&2, U32>>, k: Nat, default: U32) -> U32:
  Maybe.default(&2, U32,
    Maybe.default(&2, Maybe<&2, U32>, List.get(&2, Maybe<&2, U32>, l, k), None{}),
    default)

def numbers_only.poe(m: Maybe<&2, U32>, resto: List<&2, U32>) -> List<&2, U32>:
  match m:
    case None{}:
      resto
    case Some{v}:
      Con{v, resto}

# Só os argumentos que são números, em ordem (os outros são ignorados)
def numbers_only(args: List<String>) -> List<&2, U32>:
  match args:
    case Nil{}:
      Nil{}
    case Con{first, rest}:
      numbers_only.poe(U32.read(first), numbers_only(rest))

# Todos os argumentos como textos, numa lista `Data`
def texts(args: List<String>) -> List<&2, String>:
  match args:
    case Nil{}:
      Nil{}
    case Con{first, rest}:
      Con{first, texts(rest)}

# O k-ésimo texto (a partir de 0), ou o padrão se faltar
def text_at(l: List<&2, String>, k: Nat, default: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, l, k), default)

# Um texto como número, ou o padrão se não for número
def text_num(s: String, default: U32) -> U32:
  Maybe.default(&2, U32, U32.read(s), default)

# O k-ésimo texto como número, ou o padrão. Para quando os argumentos
# misturam textos e números (`args` só pode ser convertido uma vez).
def text_num_at(l: List<&2, String>, k: Nat, default: U32) -> U32:
  text_num(text_at(l, k, ""), default)

# ----------------------------------------------------------------
# TEMPO
# ----------------------------------------------------------------

# "123 ms" desde `t0` (um valor lido de `IO.now()`)
def tempo_desde(t0: Nat) -> IO(String):
  do IO<String>:
    t1 : Nat <- IO.now()
    return Nat.show(Nat.sub(t1, t0)) ++ " ms"

# ----------------------------------------------------------------
# SEMENTE
# ----------------------------------------------------------------

def semente.escolhe(fixa: Bool, +s: U32) -> IO(U32):
  match fixa:
    case True{}:
      IO.pure(U32, s)
    case False{}:
      IO.try(U32, IO.random_u32())

# `s`, ou um número aleatório do sistema se `s = 0`
def semente(+s: U32) -> IO(U32):
  semente.escolhe(U32.is_ne(s, 0), s)
