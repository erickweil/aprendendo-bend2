import Base

# Uma lambda `x => corpo` é um valor como outro qualquer: pode ser guardada,
# passada e devolvida. Esta devolve uma função que soma k.
def adicionador(k: U32) -> U32 -> U32:
  x => (x + k : U32)

# Uma CLOSURE (lambda que captura algo, como o `k` acima) é AFIM: pode ser
# chamada no máximo UMA vez. Receber uma e chamar uma vez é tranquilo:
def aplica(f: U32 -> U32, x: U32) -> U32:
  f(x)

# Para chamar várias vezes, use um TEMPLATE (`~`): o argumento é colado no
# lugar em tempo de compilação, sem custo nenhum. O preço é que ele não pode
# capturar variáveis locais de quem chama: só defs de topo e constantes.
def repetir(~S: Type, ~f: S -> S, n: Nat, estado: S) -> S:
  match n:
    case 0n: estado
    case 1n+p: repetir(~S, ~f, p, f(estado))

def dobra(x: U32) -> U32:
  (2 * x : U32)

def main() -> IO(Unit):
  mais5 = adicionador(5)
  +a = aplica(mais5, 10)
  # `aplica(mais5, 20)` aqui daria erro: `mais5` já foi usada

  +b = repetir(~U32, ~dobra, 10n, 1)                      # uma def de topo
  +c = repetir(~U32, ~(x => (x * 3 : U32)), 4n, 1)        # uma lambda fechada
  d = repetir(~String, ~(s => s ++ "!"), 3n, "oi")

  # A Base usa templates: List.map aplica a função a cada elemento
  e = List.map(~U32, ~U32, ~dobra, [1, 2, 3])

  # Aplicação parcial também é uma closure (afim)
  mais100 = U32.add(100)

  do IO<Unit>:
    IO.print("adicionador(5)(10) = " ++ U32.show(a))
    IO.print("dobra 10 vezes a partir de 1 = " ++ U32.show(b))
    IO.print("triplica 4 vezes a partir de 1 = " ++ U32.show(c))
    IO.print("\"oi\" com 3 exclamações = " ++ d)
    IO.print("List.map dobra [1, 2, 3] = " ++ List.show(~&1, ~U32, ~U32.show, e))
    IO.print("U32.add(100)(1) = " ++ U32.show(mais100(1)))
