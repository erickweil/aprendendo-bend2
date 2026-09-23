import Base

# type Sigma<a, b, -A: Kind(a), -B: @-x: A -> Kind(b)> is Kind(a <&> b):
#   Tuple{fst: A, snd: B(fst)}

# def Pair(A, B):
#   Sigma<&1, &1, A, _ => B>

def Pair.pure(-A: Type, -C: Type, x: C) -> U32 & C:
  (0, x)

def Pair.with(-A: Type, -B: Type, -C: Type, t: A & B, f: A -> B -> C) -> C:
  (a, b) = t
  f(a, b)

# do Pair<A, B>:
#   value : B <- t
#   (?, value)
def Pair.bind(
  -A: Type, -B: Type, -C: Type,
  t: A & B,       # Valor na direita do <-
  f: B -> B & C # Função de continuação, o argumento dela é o que vai para esquerda do <-, retorno é o valor final do bloco do
) -> B & C:
  (fst, snd) = t
  f(snd)

def teste_tupla(a: U32, b: U32) -> U32 & U32:
  do Pair<U32, U32>:
    c : U32 <- (a, b)
    d : U32 <- (1, c)
   return d

  # Acima é equivalente a:
  # Pair.bind(U32, U32, U32, (a, b), c => 
  #   Pair.bind(U32, U32, U32, (1, c), d => 
  #     Pair.pure(U32, U32, d)
  #   )
  # )

# Com template ~ a função f não permite capturar variáveis do escopo externo, funciona mais otimizado pois o compilador consegue fazer inline?
def inline_with(~A: Type, ~B: Type, ~C: Type, ~f: A -> B -> C, ab: A & B) -> C:
    (a, b) = ab
    f(a, b)

# Com closure a função f permite capturar variáveis do escopo externo
def closure_with(-A: Type, -B: Type, -C: Type, f: A -> B -> C, ab: A & B) -> C:
    (a, b) = ab
    f(a, b)

def teste_tupla_inline(a: U32, b: U32) -> U32 & U32:
  step = {(a, b) : U32 & U32}
  step = inline_with(~U32, ~U32, ~(U32 & U32), ~(x => y => ((x + y : U32), 3)), step)
  step = inline_with(~U32, ~U32, ~(U32 & U32), ~(x => y => ((x + y : U32), 4)), step)
  step = inline_with(~U32, ~U32, ~(U32 & U32), ~(x => y => ((x + y : U32), 5)), step)
  step

def main() -> IO(Unit):
  do IO<Unit>:
    u: Unit <- IO.print("== início ==")
    
    u: Unit <- Pair.with(U32, U32, IO(Unit), teste_tupla_inline(1, 2), a => b =>
      IO.print("Resultado da tupla: " ++ U32.show(a) ++ ", " ++ U32.show(b))
    )

    return Unit{}