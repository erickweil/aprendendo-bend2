import Base
import ./../utils/io.bend as IOU

# Uma `List<a, T>` é uma lista encadeada de T. A quantidade `a` diz se a
# lista pode ser duplicada: `&2` (Data, aceita `+`) ou `&1` (afim).
#
#   type List<a, -A: Kind(a)> is Kind(a):
#     Nil{}
#     Con{head: A, tail: List<a, A>}
#
# `[a, b, c]` é o mesmo que `Con{a, Con{b, Con{c, Nil{}}}}`, e `h <> t` é
# `Con{h, t}` (também como padrão no `match`).

# A Base tem os percursos de sempre como TEMPLATES (`~f`), que exigem a
# assinatura exata: `List.foldl` espera `B -> A -> B`, sem `+`. Por isso
# `U32.max` (que tem `+a, +b`) entra embrulhado numa def.
def soma(acc: U32, x: U32) -> U32:
  (acc + x : U32)

def maior(acc: U32, x: U32) -> U32:
  U32.max(acc, x)

def menor(acc: U32, x: U32) -> U32:
  U32.min(acc, x)

def quente(x: U32) -> Bool:
  (x >= 25 : U32)

def em_ordem(a: U32, b: U32) -> Bool:
  (a <= b : U32)

# Padrão aninhado: olha três elementos de uma vez. O do meio é um pico se
# for maior que os dois vizinhos (as pontas não contam).
def picos(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    # Caso de três elementos, o do meio vai ser comparado com os vizinhos
    case a <> +b <> +c <> t:
      +resto = picos(b <> c <> t)
      Bool.pick(List<&2, U32>, (b > a : U32) && (b > c : U32), b <> resto, resto)
    # Caso default, para listas com menos de 3 elementos, não há picos
    case _:
      Nil{}

def mostrar(xs: List<&2, U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, xs)

def padrao() -> List<&2, U32>:
  [18, 21, 19, 25, 22, 30, 27, 24, 28, 20]

def escolhe(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: padrao()
    case h <> t: h <> t

# Uso: listas [números...]   (sem argumentos, usa uma lista de temperaturas)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +xs : List<&2, U32> = escolhe(IOU.numbers_only(args))
    +n : U32 = U32.from_nat(List.length(&2, U32, xs))
    IO.print("lista:     " ++ mostrar(xs) ++ " (" ++ U32.show(n) ++ " elementos)")
    IO.print("maior:     " ++ U32.show(List.foldl(~&2, ~U32, ~U32, ~maior, xs, 0)))
    IO.print("menor:     " ++ U32.show(List.foldl(~&2, ~U32, ~U32, ~menor, xs, 4294967295)))
    IO.print("média:     " ++ U32.show((List.foldl(~&2, ~U32, ~U32, ~soma, xs, 0) / n : U32)))
    IO.print(">= 25:     " ++ mostrar(List.filter(~U32, ~quente, xs)))
    IO.print("picos:     " ++ mostrar(picos(xs)))
    IO.print("ordenada:  " ++ mostrar(List.sort(~U32, ~em_ordem, xs)))
    IO.print("invertida: " ++ mostrar(List.reverse(&2, U32, xs)))
    IO.print("3 primeiros: " ++ mostrar(List.take(&2, U32, xs, 3n)))
