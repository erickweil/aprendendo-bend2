# Todo código começa importando a Base (a biblioteca padrão)
import Base

# `main` é o ponto de entrada. Ele devolve uma AÇÃO de IO, e o bloco `do`
# lista as ações a executar, uma por linha.
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("Olá Bend2!")

# Para rodar:           bend ola.bend
# Para compilar:        bend ola.bend -o ../bin/ola && ../bin/ola
