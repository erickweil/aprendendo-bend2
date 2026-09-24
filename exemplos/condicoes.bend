import Base
import ./../utils/io.bend as IOU

# Não existe `if`. Há três formas de decidir.

# 1. `match` sobre um PARÂMETRO: só o caso escolhido é executado.
#    Em Nat, `2n+p` casa com "2 ou mais" (e p é o que passa de 2).
def descrever(v: Nat) -> String:
  match v:
    case 0n: "zero"
    case 1n: "um"
    case 2n+p: "mais que um"

# `match` também compara literais de U32, Char e String; `_` pega o resto.
def dia(d: U32) -> String:
  match d:
    case 0: "domingo"
    case 6: "sábado"
    case _: "dia útil"

# 2. `match` sobre um Bool CALCULADO. O `match` só olha parâmetros, então
#    `match (x > 10 : U32):` não compila: calcule a condição e passe para
#    um auxiliar, onde ela vira parâmetro.
def tamanho.step(grande: Bool) -> String:
  match grande:
    case True{}: "grande"
    case False{}: "pequeno"

def tamanho(+x: U32) -> String:
  tamanho.step((x > 10 : U32))

# 3. `Bool.pick(T, cond, se_sim, se_nao)`: uma expressão, mas ESTRITA — os
#    dois lados são SEMPRE calculados. Ótimo para escolher entre valores
#    prontos; nunca ponha uma recursão cara num dos lados (veja
#    sort_insertion.bend e AGENTS.md, Armadilha 2).
def paridade(+x: U32) -> String:
  Bool.pick(String, U32.is_even(x), "par", "ímpar")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +x : U32 = IOU.num_at(IOU.numbers(args), 0n, 7)
    IO.print(U32.show(x) ++ " é " ++ descrever(U32.to_nat(x)) ++ ", " ++ tamanho(x) ++ " e " ++ paridade(x))
    IO.print("O dia " ++ U32.show(x) ++ " (mod 7) é " ++ dia((x % 7 : U32)))
    # Operadores lógicos: &&, || e Bool.not
    IO.print("Está entre 5 e 10? " ++ Bool.show((x >= 5 : U32) && (x <= 10 : U32)))
