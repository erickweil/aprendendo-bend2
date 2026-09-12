# Todo código deve importar Base
import Base

# IO(Unit) é uma ação que não devolve valor mas pode ter efeitos colaterais, como imprimir na tela
def main() -> IO(Unit):  
  # do encadeia ações de efeito
  do IO<Unit>:
    # print, escreve e pula linha
    u : Unit <- IO.print("Exemplificando IO")

    # write, texto sem pular linha
    u : Unit <- IO.write("Olá")
    u : Unit <- IO.write(" ")
    u : Unit <- IO.write("Mundo\n")

    # Usando show para converter um valor em String
    # E o operador ++ para concatenar strings
    u : Unit <- IO.print("A resposta é: " ++ U32.show(42))
    u : Unit <- IO.print("Número Natural: " ++ Nat.show(7n))

    # O último print é o retorno da função main, que é do tipo IO(Unit)
    IO.print("Finalizado")