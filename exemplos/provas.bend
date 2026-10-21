import Base

# LEIS E PROVAS: o compilador confere que o código faz o que promete.
#
# Uma `law` afirma um fato; uma `def` com o mesmo nome o PROVA. Uma
# proposição é um tipo, e uma prova é um valor desse tipo:
#
#   {a == b : T}   "a e b são iguais" (a igualdade é um tipo)
#   {==}           prova quando os dois lados CALCULAM para o mesmo termo
#   %e : P         reescreve com e : {a == b : T}. P é o objetivo atual com
#                  `_` no lugar de b; o novo objetivo é P com a no lugar.
#   f(p)           uma chamada recursiva é a hipótese de indução
#
# Se alguma prova estiver errada ou faltando, `bend provas.bend` recusa o
# arquivo e mostra o objetivo esperado e o observado. Para ver o objetivo
# no meio de uma prova, troque o resto dela por `?nome`: o erro mostra o que
# falta provar e as variáveis disponíveis. As provas são apagadas
# na compilação: não custam nada no binário.
#
# Num projeto, as leis ficam em LAWS.bend (escritas pelo humano) e as provas
# em PROOF.bend (escritas por quem implementa); veja o GUIDE.md.

# ----------------------------------------------------------------
# 1. "x + 0 = x" (o exemplo do GUIDE)
# ----------------------------------------------------------------
# `Nat.add` desce pelo PRIMEIRO argumento, então `0 + x` já calcula para x,
# mas `x + 0` precisa de indução.
law soma_zero:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}

def soma_zero(x):
  match x:
    case 0n:
      {==}                                         # 0 + 0 calcula para 0
    case 1n+p:
      # objetivo: 1 + (p + 0) == 1 + p. A hipótese soma_zero(p) diz
      # p + 0 == p: reescreve o `_` e sobra 1 + (p + 0) == 1 + (p + 0).
      %soma_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

# ----------------------------------------------------------------
# 2. Um lema, e uma lei sobre uma função da Base que o usa
# ----------------------------------------------------------------
law soma_suc:
  for a: Nat
  for b: Nat
  {1n+Nat.add(a, b) == Nat.add(a, 1n+b) : Nat}

def soma_suc(a, b):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %soma_suc(p, b) : {2n+Nat.add(p, b) == 1n+_ : Nat}
      {==}

# `Nat.double(n)` (da Base) soma 2 a cada passo. Ele é mesmo n + n?
law dobro_soma:
  for n: Nat
  {Nat.double(n) == Nat.add(n, n) : Nat}

def dobro_soma(n):
  match n:
    case 0n:
      {==}
    case 1n+ +p:                                     # p é usado duas vezes
      # objetivo: 2 + dobro(p) == 1 + (p + (1 + p))
      %soma_suc(p, p) : {2n+Nat.double(p) == 1n+_ : Nat}
      # agora:    2 + dobro(p) == 2 + (p + p)
      %dobro_soma(p) : {2n+Nat.double(p) == 2n+_ : Nat}
      {==}

# ----------------------------------------------------------------
# 3. Uma lei genérica sobre listas
# ----------------------------------------------------------------
law tamanho_concat:
  for -A: Data
  for xs: List<&2, A>
  for ys: List<&2, A>
  {List.length(&2, A, List.append(&2, A, xs, ys)) == Nat.add(List.length(&2, A, xs), List.length(&2, A, ys)) : Nat}

def tamanho_concat(A, xs, ys):
  match xs:
    case Nil{}:
      {==}
    case h <> t:
      %tamanho_concat(A, t, ys) : {1n+List.length(&2, A, List.append(&2, A, t, ys)) == 1n+_ : Nat}
      {==}

# ----------------------------------------------------------------
# 4. Uma prova usada como valor
# ----------------------------------------------------------------
# Um tipo de retorno pode ser uma igualdade: esta def "calcula" a prova de
# que dobro(21) é 21 + 21 aplicando a lei geral a um caso.
def dobro_21() -> {Nat.double(21n) == Nat.add(21n, 21n) : Nat}:
  dobro_soma(21n)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("Se este programa rodou, todas as provas conferem:")
    IO.print("  x + 0 = x, dobro(n) = n + n, |xs ++ ys| = |xs| + |ys|")
    IO.print("  dobro(21) = " ++ Nat.show(Nat.double(21n)))
