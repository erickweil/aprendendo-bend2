import Base
import ./../utils/io.bend as IOU
import ./../utils/random.bend as R

# O bloco `do` não é só para IO: funciona com qualquer tipo M que tenha
# `M.bind` e `M.pure`. Cada linha `x : A <- m` vira `M.bind(A, R, m, x => ..)`
# e `return e` vira `M.pure(R, e)`.

# ----------------------------------------------------------------
# MAYBE: um `None` em qualquer passo encerra o bloco com `None`
# ----------------------------------------------------------------
def soma_textos(a: String, b: String) -> Maybe<&2, U32>:
  do Maybe<&2, U32>:
    x : U32 <- U32.read(a)
    y : U32 <- U32.read(b)
    return (x + y : U32)

# ----------------------------------------------------------------
# RESULT: como o Maybe, mas o erro carrega uma mensagem
# ----------------------------------------------------------------
def dividir(+a: U32, +b: U32) -> Result<&2, &2, String, U32>:
  match b:
    case 0: Fail{"divisão por zero"}
    case _: Done{(a / b : U32)}

def ler.step(m: Maybe<&2, U32>, s: String) -> Result<&2, &2, String, U32>:
  match m:
    case None{}: Fail{"\"" ++ s ++ "\" não é número"}
    case Some{v}: Done{v}

def ler(+s: String) -> Result<&2, &2, String, U32>:
  ler.step(U32.read(s), s)

def media(a: String, b: String, n: String) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    x : U32 <- ler(a)
    y : U32 <- ler(b)
    k : U32 <- ler(n)
    q : U32 <- dividir((x + y : U32), k)
    return q

def mostra_result(r: Result<&2, &2, String, U32>) -> String:
  match r:
    case Done{v}: "Ok: " ++ U32.show(v)
    case Fail{e}: "Erro: " ++ e

# ----------------------------------------------------------------
# UMA MÔNADA PRÓPRIA: sorteios sem estado global
# ----------------------------------------------------------------
# Um `Rand<A>` é "uma função que recebe a semente e devolve a próxima semente
# junto com um A". O `do` esconde a semente passando de mão em mão.
type Rand<-A: Type> is Type:
  Rand{run: U32 -> U32 & A}

def Rand.run(-A: Type, r: Rand<A>, s: U32) -> U32 & A:
  Rand{f} = r
  f(s)

def Rand.pure(-A: Type, x: A) -> Rand<A>:
  Rand{s => (s, x)}

def Rand.bind.passo(-A: Type, -B: Type, r: U32 & A, f: A -> Rand<B>) -> U32 & B:
  (s, a) = r
  Rand.run(B, f(a), s)

def Rand.bind(-A: Type, -B: Type, m: Rand<A>, f: A -> Rand<B>) -> Rand<B>:
  Rand{s => Rand.bind.passo(A, B, Rand.run(A, m, s), f)}

# Um dado de `lados` faces: sorteia com a semente e devolve a próxima
def dado(lados: U32) -> Rand<U32>:
  Rand{+s => (R.step(s), (R.range(s, lados) + 1 : U32))}

def tres_dados() -> Rand<U32>:
  do Rand<U32>:
    a : U32 <- dado(6)
    b : U32 <- dado(6)
    c : U32 <- dado(6)
    return (a + b + c : U32)

def resultado(r: U32 & U32) -> String:
  (s, v) = r
  U32.show(v)

# Uso: monad [semente=0: aleatória]
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    s : U32 <- IOU.semente(IOU.num_at(IOU.numbers(args), 0n, 0))
    IO.print("Maybe:  \"40\" + \"2\"  = " ++ Maybe.show(~&2, ~U32, ~U32.show, soma_textos("40", "2")))
    IO.print("Maybe:  \"40\" + \"x\"  = " ++ Maybe.show(~&2, ~U32, ~U32.show, soma_textos("40", "x")))
    IO.print("Result: (10 + 20) / 3 -> " ++ mostra_result(media("10", "20", "3")))
    IO.print("Result: (10 + 20) / 0 -> " ++ mostra_result(media("10", "20", "0")))
    IO.print("Result: (dez + 20) / 3 -> " ++ mostra_result(media("dez", "20", "3")))
    IO.print("Rand:   três dados somam " ++ resultado(Rand.run(U32, tres_dados(), s)))
