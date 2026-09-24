import Base

# `IO(A)` é uma AÇÃO que, quando executada, produz um `A` e pode ter efeitos
# (imprimir, ler um arquivo, esperar...). `IO(Unit)` não produz nada útil.
# O bloco `do IO<Unit>:` executa as ações em ordem.
def main() -> IO(Unit):
  do IO<Unit>:
    # print escreve e pula linha; write escreve sem pular
    IO.print("Exemplificando IO")
    IO.write("Olá")
    IO.write(" ")
    IO.write("Mundo\n")

    # `show` converte um valor em String e `++` concatena
    IO.print("A resposta é: " ++ U32.show(42))
    IO.print("Número natural: " ++ Nat.show(7n))
    IO.print("Real: " ++ F32.show(3.25))
    IO.print("Booleano: " ++ Bool.show(True{}))

    # `x : T <- acao` executa a ação e dá nome ao resultado.
    # `IO.get_env` pode falhar; `IO.try` tira o valor ou encerra com o erro.
    nome : String <- IO.try(String, IO.get_env("USER"))
    IO.print("Olá, " ++ nome ++ "!")

    # `x : T = valor` dá nome a um valor PURO no meio do bloco
    dobro : U32 = (21 * 2 : U32)
    IO.print("O dobro de 21 é " ++ U32.show(dobro))

    # Os argumentos da linha de comando (veja utils/io.bend para lê-los)
    args : List<String> <- IO.args()
    IO.print(Nat.show(List.length(&1, String, args)) ++ " argumento(s)")

    # A saída de erro
    IO.print_err("(isto vai para a saída de erro)")
