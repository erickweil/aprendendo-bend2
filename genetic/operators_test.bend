import Base
import ./operators.bend as Op
import ./../utils/arrays.bend as Arr
import ./../utils/random.bend as R

# ================================================================
# TESTES DOS OPERADORES — foco no OX1
# ================================================================
# O invariante que importa no OX1 é UM: cada filho é uma permutação do mesmo
# multiconjunto de chaves dos pais. Se isso quebra, o genoma deixa de ser um
# sudoku (ou um horário) e o motor passa a otimizar lixo — em silêncio, porque
# a aptidão continua sendo um número.
#
# Layout do array de teste (profundidade 8 = 256 slots):
#     0.. 63  a fatia (até 64 genes)
#    64..127  marcas do OX1        (uma por chave)
#   128..191  contagem do verificador
#
# 64 chaves é de propósito: é o dobro do que uma máscara de bits num U32
# aguenta. É este caso que prova que o operador serve para o quadro de
# horário, não só para os 9 dígitos do sudoku.

def MARK_BASE() -> U32:
  64

def VER_BASE() -> U32:
  128

def key_id(+x: U32) -> U32:
  x

# ---- construir permutações ----

def po_idx(+x: U32, +c: U32, +k: U32) -> U32:
  k

def identidade(+n: U32) -> Array<U32>:
  Arr.map_range(~U32, ~po_idx, [0 : U32^8n], 0, n)

# Fisher-Yates sobre [0, n): embaralha de trás para frente
def baralha.go(k: Nat, a: Array<U32>, +i: U32, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      a
    case 1n+p:
      baralha.go(p, Arr.swap_at(~U32, a, i, R.range(seed, U32.inc(i))), (i - 1 : U32), R.step(seed))

def baralha(a: Array<U32>, +n: U32, +seed: U32) -> Array<U32>:
  baralha.go(U32.to_nat((n - 1 : U32)), a, (n - 1 : U32), seed)

def perm(+n: U32, +seed: U32) -> Array<U32>:
  baralha(identidade(n), n, seed)

# ---- verificador: a fatia [0,n) é uma permutação de [0,n)? ----
# Conta cada valor na faixa do verificador e confere que toda contagem é 1.

def zera(+x: U32, +c: U32, +k: U32) -> U32:
  0

def conta_um(+x: U32, +c: U32, +k: U32) -> U32:
  U32.inc(x)

# soma 1 na posição CHECK+valor, para cada gene da fatia
def marca.um(r: Array<U32> & U32) -> Array<U32>:
  (a, +v) = r
  Arr.map_range(~U32, ~conta_um, a, (VER_BASE() + v : U32), 1)

def marca.go(k: Nat, a: Array<U32>, +i: U32) -> Array<U32>:
  match k:
    case 0n:
      a
    case 1n+p:
      marca.go(p, marca.um(Array.get(U32, a, i)), (i + 1 : U32))

def todas_um(+x: U32, acc: U32, +k: U32) -> U32:
  Bool.pick(U32, U32.is_eq(x, 1), acc, 0)

def ok_de(r: Array<U32> & U32) -> Bool:
  (a, +v) = r
  U32.is_ne(v, 0)

def eh_perm(a: Array<U32>, +n: U32) -> Bool:
  ok_de(Arr.fold_range(~U32, ~U32, ~todas_um,
    marca.go(U32.to_nat(n), Arr.map_range(~U32, ~zera, a, VER_BASE(), n), 0),
    1, VER_BASE(), n))

# ---- uma rodada de OX1: os dois filhos são permutações? ----

def rodada.ver(r: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>), +n: U32) -> Bool:
  (filhos, pais) = r
  (ca, cb) = filhos
  Bool.and(eh_perm(ca, n), eh_perm(cb, n))

def rodada(+n: U32, +seed: U32, +cruza: Bool) -> Bool:
  rodada.ver(Op.breed_ox1_slice(~key_id,
    [0 : U32^8n], [0 : U32^8n],
    perm(n, R.split.fst(seed)), perm(n, R.split.snd(seed)),
    0, n, MARK_BASE(), cruza, R.split.trd(seed)), n)

# ---- fuzz: `k` rodadas, conta quantas passaram ----

def fuzz.go(k: Nat, +n: U32, +acc: U32, +seed: U32, +cruza: Bool) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      fuzz.go(p, n, (acc + Bool.to_u32(rodada(n, seed, cruza)) : U32), R.step(seed), cruza)

def fuzz(+n: U32, +vezes: U32, +seed: U32, +cruza: Bool) -> String:
  U32.show(fuzz.go(U32.to_nat(vezes), n, 0, seed, cruza)) ++ "/" ++ U32.show(vezes)

def check(rot: String, +obtido: String, +esperado: String) -> String:
  +ok = String.eq(obtido, esperado)
  Bool.pick(String, ok, "  ok    ", "  FALHA ") ++ rot ++ ": " ++ obtido ++
  Bool.pick(String, ok, "", " (esperado " ++ esperado ++ ")")

# sanidade do próprio verificador: uma permutação passa, um array com repetido falha
def teste_verificador_bom() -> String:
  Bool.show(eh_perm(perm(8, 999), 8))

def teste_verificador_ruim() -> String:
  Bool.show(eh_perm(Arr.map_range(~U32, ~zera, perm(8, 999), 0, 2), 8))

def main() -> IO(Unit):
  do IO<Unit>:
    u : Unit <- IO.print("== verificador (sanidade) ==")
    u : Unit <- IO.print(check("permutação é aceita", teste_verificador_bom(), "True"))
    u : Unit <- IO.print(check("com valor repetido é rejeitada", teste_verificador_ruim(), "False"))
    u : Unit <- IO.print("== OX1: filhos são permutações? ==")
    u : Unit <- IO.print(check("n=9  (sudoku), 200 rodadas, cruzando", fuzz(9, 200, 1, True{}), "200/200"))
    u : Unit <- IO.print(check("n=9  (sudoku), 200 rodadas, sem cruzar", fuzz(9, 200, 7, False{}), "200/200"))
    u : Unit <- IO.print(check("n=8  (potência de 2), 200 rodadas", fuzz(8, 200, 3, True{}), "200/200"))
    u : Unit <- IO.print(check("n=33 (passa de 32 chaves!), 200 rodadas", fuzz(33, 200, 5, True{}), "200/200"))
    IO.print(check("n=64 (dobro do U32), 200 rodadas", fuzz(64, 200, 11, True{}), "200/200"))
