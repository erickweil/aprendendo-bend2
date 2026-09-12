import Base

def newline() -> String:
  "\n"

def main() -> IO(Unit):
  # Podemos criar uma binding quase igual variáveis Python
  # Porém elas são imutáveis e só podem ser usadas uma vez
  # Para permtir usar duas vezes precisamos do + antes do nome da variável
  +ln = newline()

  # msg não foi modificada, apenas criamos uma nova binding com o mesmo nome
  # Exemplo re-utilizando a mesma mensagem para concatenar
  msg = "Oi tudo bem?" ++ ln
  msg = msg ++ "Experimentando a linguagem Bend!" ++ ln
  msg = msg ++ "Espero que isso apareça no terminal..." ++ ln

  IO.write(msg)

  