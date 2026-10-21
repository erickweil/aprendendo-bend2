import Base

def main() -> IO(Unit):
  # Um "binding" parece uma variável do Python, mas é IMUTÁVEL e, por padrão,
  # só pode ser USADO UMA VEZ (como um valor sem `Copy` no Rust).
  # Com `+` na frente ele pode ser usado quantas vezes quiser.
  # Um literal solto precisa do tipo (`: String`); o valor de uma chamada,
  # como `msg ++ ln` abaixo, já tem tipo conhecido.
  +ln : String = "\n"

  # Repetir o nome cria um binding NOVO que esconde o anterior (shadowing).
  # O `msg` anterior foi usado (consumido) na concatenação.
  msg = "Oi tudo bem?" ++ ln
  msg = msg ++ "Experimentando a linguagem Bend!" ++ ln
  msg = msg ++ "Espero que isso apareça no terminal..." ++ ln

  # Descomente e veja o erro "consumed more than once":
  # outra = msg ++ msg

  # `-` marca um binding APAGADO: ele existe só para o verificador de tipos
  # e some do programa compilado (útil em provas; veja provas.bend).
  IO.write(msg)
