import Base
import ./../utils/io.bend as IOU

# Uma recursão que devolve IO: cada volta imprime e depois continua. O
# `do` encadeia a impressão com a chamada recursiva, e o Nat decrescente é o
# que garante que termina. A memória fica constante: medido no nativo, 1,9 MB
# contando até 4 milhões.
def contar(combustivel: Nat, +contador: U32) -> IO(Unit):
  match combustivel:
    case 0n:
      IO.print("fim!")
    case 1n+p:
      do IO<Unit>:
        IO.print(U32.show(contador))
        contar(p, (contador + 1 : U32))

# O mesmo com a Base: `List.for_each` executa uma ação por elemento, e
# `List.range(n)` é a lista [0, 1, ..., n-1] — montada inteira na memória
# antes de começar (~16 bytes por elemento).
def mostra(n: Nat) -> IO(Unit):
  IO.print("  item " ++ Nat.show(n))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOU.num_at(IOU.numbers(args), 0n, 5)
    contar(U32.to_nat(n), 1)
    IO.print("De novo, com List.for_each:")
    List.for_each(~&2, ~Nat, ~mostra, List.range(U32.to_nat(n)))
