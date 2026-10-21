import Base
import ./../utils/io.bend as IOU

# Não há `for` nem `while`: repetição é recursão. E toda recursão precisa
# TERMINAR — o compilador verifica. Descomente e veja o erro:
# def infinito(n: Nat) -> Nat:
#   infinito(n)

# Como o compilador sabe que termina: a chamada recursiva recebe um PEDAÇO
# menor do parâmetro. `1n+p` separa n em "um mais p", e p é menor que n.
# (Aqui `+p` no padrão deixa usar p duas vezes.)
#
# A soma só acontece DEPOIS que a chamada recursiva volta, então cada chamada
# fica pendente na memória: medido no nativo, ~16 bytes por chamada
# (`repetindo 100000000` usa 1,5 GB).
def soma_ate(n: Nat) -> U32:
  match n:
    case 0n: 0
    case 1n+ +p: (U32.from_nat(p) + 1 + soma_ate(p) : U32)

# Com acumulador, a chamada recursiva é a ÚLTIMA coisa feita (tail call) e
# vira um laço simples no binário: memória constante, qualquer que seja n.
def fatorial(n: Nat, +i: U32, +acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: fatorial(p, (i + 1 : U32), (acc * i : U32))

# Quando o número de passos não é conhecido, o Nat vira COMBUSTÍVEL: um
# limite que garante o fim, enquanto o trabalho de verdade é feito em U32.
# (`U32.to_nat` custa O(1) no binário: lá um Nat é uma palavra de máquina.)
def collatz(combustivel: Nat, +x: U32, +passos: U32) -> U32:
  match combustivel:
    case 0n: passos
    case 1n+p:
      match x:
        case 1: passos
        case _: collatz(p, Bool.pick(U32, U32.is_even(x), (x / 2 : U32), (3 * x + 1 : U32)), (passos + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOU.num_at(IOU.numbers(args), 0n, 10)
    IO.print("1 + 2 + ... + " ++ U32.show(n) ++ " = " ++ U32.show(soma_ate(U32.to_nat(n))))
    IO.print(U32.show(n) ++ "! = " ++ U32.show(fatorial(U32.to_nat(n), 1, 1)) ++ " (dá a volta acima de 12!)")
    IO.print("Collatz de " ++ U32.show(n) ++ " chega a 1 em " ++ U32.show(collatz(1000n, n, 0)) ++ " passos")
