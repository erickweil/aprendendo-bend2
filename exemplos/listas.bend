import Base

def pick(-A: Type, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

# Em Bend2 toda função de dois parâmetros def f(a, b) é na verdade a => b => (...)
# A função f recebe um elemento da lista e o acumulado e deve retornar novamente o acumulado
def reduce(~A: Data, ~S: Data, ~f: @+a: S -> @+x: A -> S, xs: List<&2, A>, acc: S) -> S:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      reduce(~A, ~S, ~f, t, f(acc, h))

def max_u32() -> U32:
  4294967295

def somar(+acc: U32, +x: U32) -> U32:
  (acc + x : U32)

def contar(+acc: U32, +x: U32) -> U32:
  (acc + 1 : U32)

def max(+acc: U32, +x: U32) -> U32:
  pick(U32, (x > acc : U32), x, acc)

def min(+acc: U32, +x: U32) -> U32:
  pick(U32, (x < acc : U32), x, acc)

def mostrar(xs: List<&2, U32>) -> String:
  reduce(~U32, ~String, ~(acc => x => acc ++ U32.show(x) ++ ", "), xs, "")

# Padrão aninhado: olha três elementos de uma vez. O do meio é pico
# se for maior que os dois vizinhos. Extremos não contam.
def picos(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    # Caso de três elementos, o do meio vai ser comparado com os vizinhos
    case Con{a, Con{b, Con{c, t}}}:
      +resto = picos(Con{b, Con{c, t}})
      # Só adiciona na lista de retorno se é maior que os vizinhos
      pick(List<&2, U32>, (b > a && b > c : U32), 
        Con{b, resto}, 
        resto
      )
    # Caso default, para listas com menos de 3 elementos, não há picos
    case outro:
      Nil{}

# um List<a, T> é uma lista encadeada de elementos do tipo T
# o tipo a indica se pode ou não duplicação, usar &2 para permitir duplicação
# 
#  type List<a, -A: Kind(a)> is Kind(a):
#    Nil{}
#    Con{head: A, tail: List<a, A>}
#
# Um [a, b, c] é o mesmo que Con{a, Con{b, Con{c, Nil{}}}}.
def temperaturas() -> List<&2, U32>:
  [18, 21, 19, 25, 22, 30, 27, 24, 28, 20]

def main() -> IO(Unit):
  +temps = temperaturas()
  maior = reduce(~U32, ~U32, ~max, temps, 0)
  menor = reduce(~U32, ~U32, ~min, temps, max_u32())

  soma = reduce(~U32, ~U32, ~somar, temps, 0)
  contagem = reduce(~U32, ~U32, ~contar, temps, 0)
  media = (soma / contagem : U32)
  do IO<Unit>:
    u : Unit <- IO.print("temps:  " ++ mostrar(temps))
    u : Unit <- IO.print("maior:  " ++ U32.show(maior))
    u : Unit <- IO.print("menor:  " ++ U32.show(menor))
    u : Unit <- IO.print("media:  " ++ U32.show(media))
    IO.print("picos:  " ++ mostrar(picos(temps)))