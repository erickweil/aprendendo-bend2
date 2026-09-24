import Base

# Os tipos básicos da Base. Um literal precisa saber o próprio tipo: em
# argumento ou retorno de função ele vem do contexto; num binding solto,
# escreva o tipo com o let tipado `x : T = valor` (ou anote: `{20 : U32}`).
def main() -> IO(Unit):
  +a : U32 = 20            # inteiro sem sinal, 32 bits; dá a volta: 0 - 1 = 4294967295
  +n : Nat = 7n            # natural: é o que garante que um laço termina
  +x : F32 = 1.5           # real de 32 bits
  c : Char = 'B'           # um caractere (o código Unicode dentro de um U32)
  s : String = "texto"     # uma lista encadeada de Char
  b : Bool = True{}        # um tipo como outro qualquer: True{} ou False{}

  # Operadores pegam o tipo da anotação em volta: (a + b : T)
  +soma = (a + a + a : U32)
  +raiz = F32.sqrt((x * 8.0 : F32))

  # Tipos diferentes não se misturam: converta com T.to_x / T.from_x.
  # Aqui `total` passa a ser um Nat; o nome pode ser reusado com outro tipo.
  +total = (U32.to_nat(soma) + n : Nat)
  total = Nat.show(total)

  do IO<Unit>:
    IO.print("U32:    " ++ U32.show(soma) ++ "   (0 - 1 dá " ++ U32.show((0 - 1 : U32)) ++ ")")
    IO.print("Nat:    " ++ total)
    IO.print("F32:    " ++ F32.show(raiz) ++ "   (" ++ U32.show(soma) ++ " como F32: " ++ F32.show(U32.to_f32(soma)) ++ ")")
    IO.print("Char:   " ++ Char.show(c) ++ " tem código " ++ U32.show(Char.to_u32('B')))
    IO.print("String: \"" ++ s ++ "\" tem " ++ Nat.show(String.length("texto")) ++ " letras")
    IO.print("Bool:   " ++ Bool.show(b))
