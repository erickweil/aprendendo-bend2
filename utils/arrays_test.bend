import Base
import ./arrays.bend as Arr
import ./tuples.bend as T

# Testes de utils/arrays.bend
#   bend utils/arrays_test.bend --check-only
#   bend utils/arrays_test.bend -o bin/arrays_test && ./bin/arrays_test

# ----------------------------------------------------------------
# dados: arrays de 8 posições marcados pelo índice
# ----------------------------------------------------------------

def idx(v: U32, +c: U32, i: U32) -> U32:
  i

def idx_mais(v: U32, +c: U32, i: U32) -> U32:
  (i + c : U32)

# [0, 1, 2, ..., 7]
def marcado() -> Array<U32>:
  Arr.for_each(~U32, ~U32, ~idx, [0 : U32*8n], 0)

# [100, 101, ..., 107]
def marcado100() -> Array<U32>:
  Arr.for_each(~U32, ~U32, ~idx_mais, [0 : U32*8n], 100)

def mostra(arr: Array<U32>) -> String:
  Arr.show(~U32, ~U32.show, arr)

def mostra2(r: Array<U32> & Array<U32>) -> String:
  (a, b) = r
  "a=" ++ mostra(a) ++ " b=" ++ mostra(b)

# ----------------------------------------------------------------
# percursos
# ----------------------------------------------------------------

def soma(+x: U32, acc: U32, i: U32) -> U32:
  (x + acc : U32)

def dobra_par(v: U32, acc: U32, +ctx: U32, i: U32) -> U32 & U32:
  +vv = v
  ((vv * 2 : U32), (acc + vv : U32))

def zip_soma(a: U32, b: U32, i: U32) -> U32:
  (a + b : U32)

def teste_reduce() -> String:
  T.with(Array<U32>, U32, String, Arr.reduce(~U32, ~U32, ~soma, marcado(), 0), arr => +s =>
    mostra(arr) ++ " soma=" ++ U32.show(s))

# fold_rot: dobra cada elemento e soma os originais. Rotaciona uma posição.
def teste_fold_rot() -> String:
  T.with3(Array<U32>, U32, U32, String,
    Arr.fold_rot(~U32, ~U32, ~U32, ~dobra_par, T.pair(Array<U32>, U32, marcado(), 999), 0, 0),
    arr => +h => +acc => mostra(arr) ++ " soma=" ++ U32.show(acc))

def teste_for_each_rot() -> String:
  T.with(Array<U32>, U32, String,
    Arr.for_each_rot(~U32, ~U32, ~idx, T.pair(Array<U32>, U32, [0 : U32*8n], 999), 0),
    arr => +h => mostra(arr))

def teste_zip_with() -> String:
  mostra(Arr.zip_with(~U32, ~U32, ~zip_soma, marcado(), marcado100()))

# ----------------------------------------------------------------
# faixas com elemento Type: Array<Array<U32>>, cada slot um "genoma"
# ----------------------------------------------------------------

def genome(+v: U32) -> Array<U32>:
  Array.new(U32, 1n, v)

def hole() -> Array<U32>:
  [99 : U32*1n]

def pop_a() -> Array<Array<U32>>:
  ANode{ANode{ALeaf{genome(0)}, ALeaf{genome(1)}}, ANode{ALeaf{genome(2)}, ALeaf{genome(3)}}}

def pop_b() -> Array<Array<U32>>:
  ANode{ANode{ALeaf{genome(100)}, ALeaf{genome(101)}}, ANode{ALeaf{genome(102)}, ALeaf{genome(103)}}}

# lê o primeiro gene do slot i; descarta o genoma (é só teste), então o slot
# fica com o buraco: não leia o mesmo slot duas vezes
def gene_at.v(pop: Array<Array<U32>>, r: Array<U32> & U32) -> Array<Array<U32>> & U32:
  (g, +v) = r
  (pop, v)

def gene_at.read(r: Array<Array<U32>> & Array<U32>) -> Array<Array<U32>> & U32:
  (pop, g) = r
  gene_at.v(pop, Array.get(U32, g, 0))

def gene_at(pop: Array<Array<U32>>, hole: Array<U32>, +i: U32) -> Array<Array<U32>> & U32:
  gene_at.read(Array.swap(Array<U32>, pop, i, hole))

def dois.fin(r: Array<Array<U32>> & U32, +v0: U32) -> String:
  (pop, +v1) = r
  U32.show(v0) ++ "," ++ U32.show(v1)

def dois(r: Array<Array<U32>> & U32, +ib: U32) -> String:
  (pop, +v0) = r
  dois.fin(gene_at(pop, hole(), ib), v0)

def le_0_e_3(r: Array<Array<U32>> & Array<U32>) -> String:
  (pop, h) = r
  dois(gene_at(pop, h, 0), 3)

def teste_swap_at_hole() -> String:
  le_0_e_3(Arr.swap_at_hole(~Array<U32>, T.pair(Array<Array<U32>>, Array<U32>, pop_a(), hole()), 0, 3))

def teste_swap_at_hole_mesmo() -> String:
  le_0_e_3(Arr.swap_at_hole(~Array<U32>, T.pair(Array<Array<U32>>, Array<U32>, pop_a(), hole()), 2, 2))

def range_hole.fin(r: Array<Array<U32>> & U32, +va: U32) -> String:
  (pop, +vb) = r
  U32.show(va) ++ "," ++ U32.show(vb)

def range_hole.b(ra: Array<Array<U32>> & U32, arr_b: Array<Array<U32>>) -> String:
  (arr_a, +va) = ra
  range_hole.fin(gene_at(arr_b, hole(), 1), va)

def range_hole.go(st: (Array<Array<U32>> & Array<Array<U32>>) & Array<U32>) -> String:
  (ab, h) = st
  (arr_a, arr_b) = ab
  range_hole.b(gene_at(arr_a, h, 1), arr_b)

def teste_swap_range_hole() -> String:
  range_hole.go(Arr.swap_range_hole(~Array<U32>, pop_a(), pop_b(), hole(), 1, 2))

# ----------------------------------------------------------------

def check(rot: String, +obtido: String, +esperado: String) -> String:
  +ok = String.eq(obtido, esperado)
  Bool.pick(String, ok, "  ok    ", "  FALHA ") ++ rot ++ ": " ++ obtido ++
    Bool.pick(String, ok, "", "\n          esperado: " ++ esperado)

def main() -> IO(Unit):
  do IO<Unit>:
    u : Unit <- IO.print("== percursos ==")
    u : Unit <- IO.print(check("for_each(i)", mostra(marcado()), "[0, 1, 2, 3, 4, 5, 6, 7]"))
    u : Unit <- IO.print(check("reduce(soma)", teste_reduce(), "[0, 1, 2, 3, 4, 5, 6, 7] soma=28"))
    u : Unit <- IO.print(check("fold_rot(dobra) + soma", teste_fold_rot(), "[14, 0, 2, 4, 6, 8, 10, 12] soma=28"))
    u : Unit <- IO.print(check("for_each_rot(i)", teste_for_each_rot(), "[7, 0, 1, 2, 3, 4, 5, 6]"))
    u : Unit <- IO.print(check("zip_with(+)", teste_zip_with(), "[100, 102, 104, 106, 108, 110, 112, 114]"))
    u : Unit <- IO.print("== faixas, elemento Data ==")
    u : Unit <- IO.print(check("copy_range(from=2,count=3)",
      mostra2(Arr.copy_range(~U32, marcado(), marcado100(), 2, 3)),
      "a=[0, 1, 102, 103, 104, 5, 6, 7] b=[100, 101, 102, 103, 104, 105, 106, 107]"))
    u : Unit <- IO.print(check("swap_range(from=2,count=4)",
      mostra2(Arr.swap_range(~U32, marcado(), marcado100(), 2, 4)),
      "a=[0, 1, 102, 103, 104, 105, 6, 7] b=[100, 101, 2, 3, 4, 5, 106, 107]"))
    u : Unit <- IO.print(check("swap_range(count=0) intacto",
      mostra2(Arr.swap_range(~U32, marcado(), marcado100(), 3, 0)),
      "a=[0, 1, 2, 3, 4, 5, 6, 7] b=[100, 101, 102, 103, 104, 105, 106, 107]"))
    u : Unit <- IO.print(check("fill(9, from=5, count=2)",
      mostra(Arr.fill(~U32, marcado(), 9, 5, 2)), "[0, 1, 2, 3, 4, 9, 9, 7]"))
    u : Unit <- IO.print(check("swap_at(0,3)", mostra(Arr.swap_at(~U32, marcado(), 0, 3)), "[3, 1, 2, 0, 4, 5, 6, 7]"))
    u : Unit <- IO.print(check("swap_at(2,2) intacto", mostra(Arr.swap_at(~U32, marcado(), 2, 2)), "[0, 1, 2, 3, 4, 5, 6, 7]"))
    u : Unit <- IO.print("== faixas, elemento Type (buraco) ==")
    u : Unit <- IO.print(check("swap_at_hole(0,3) -> slots 0,3", teste_swap_at_hole(), "3,0"))
    u : Unit <- IO.print(check("swap_at_hole(2,2) intacto", teste_swap_at_hole_mesmo(), "0,3"))
    IO.print(check("swap_range_hole(from=1,count=2) -> a[1],b[1]", teste_swap_range_hole(), "101,1"))
