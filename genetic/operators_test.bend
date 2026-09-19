import Base
import ./../utils/random.bend as R
import ./utils/genes.bend as V
import ./operators.bend as Op

# ================================================================
# TESTE DOS CRUZAMENTOS (operators.bend)
# ================================================================
# Todo cruzamento produz DOIS filhos. Invariantes verificados, em tamanho
# pequeno (varredura de sementes) e em tamanho grande (100 mil genes):
#  - posicionais: os filhos são COMPLEMENTARES — em cada posição, os genes dos
#    dois filhos são os dois genes dos pais naquela posição (o que implica
#    comprimento preservado e todo gene vindo de um pai na mesma posição)
#  - OX1: os dois filhos são permutações válidas; com pais iguais devolve os
#    pais; o exemplo do Rust dá os mesmos dois filhos; funciona para qualquer
#    tipo de gene que tenha uma `~key`
# ================================================================

def eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Nil{} Con{y, ys}:
      False{}
    case Con{x, xs} Nil{}:
      False{}
    case Con{x, xs} Con{y, ys}:
      Bool.and(U32.is_eq(x, y), eq(xs, ys))

# Em cada posição, {ca[i], cb[i]} = {a[i], b[i]}, e os quatro têm o mesmo
# comprimento
def complementary(ca: List<&2, U32>, cb: List<&2, U32>, a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match ca cb a b:
    case Nil{} Nil{} Nil{} Nil{}:
      True{}
    case Con{+z, zs} Con{+w, ws} Con{+x, xs} Con{+y, ys}:
      Bool.and(Bool.or(Bool.and(U32.is_eq(z, x), U32.is_eq(w, y)), Bool.and(U32.is_eq(z, y), U32.is_eq(w, x))),
               complementary(zs, ws, xs, ys))
    case _ _ _ _:
      False{}

def pair_complementary(r: List<&2, U32> & List<&2, U32>, a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  (ca, cb) = r
  complementary(ca, cb, a, b)

def pair_eq(r: List<&2, U32> & List<&2, U32>, a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  (ca, cb) = r
  Bool.and(eq(ca, a), eq(cb, b))

def pair_perm(r: List<&2, U32> & List<&2, U32>, +n: U32) -> Bool:
  (ca, cb) = r
  Bool.and(V.is_permutation(ca, n), V.is_permutation(cb, n))

def offset(l: List<&2, U32>, +k: U32) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{(h + k : U32), offset(t, k)}

def key_u32(g: U32) -> U32:
  g

def ok(b: Bool) -> U32:
  Bool.to_u32(b)

# --- posicionais: pais [0..n) e [1M..1M+n) ---
def check_pos(+n: U32, +s: U32) -> U32:
  +a = V.perm_range(n)
  +b = offset(V.perm_range(n), 1000000)
  (ok(pair_complementary(Op.cross_uniform(U32, a, b, s), a, b)) +
   ok(pair_complementary(Op.cross_1point(U32, a, b, n, s), a, b)) +
   ok(pair_complementary(Op.cross_2point(U32, a, b, n, s), a, b)) : U32)

# --- OX1: validade e identidade ---
def check_ox1(+n: U32, +s: U32) -> U32:
  +a = V.perm_random(n, s)
  +b = V.perm_random(n, R.step(s))
  (ok(pair_perm(Op.cross_ox1(~U32, ~key_u32, a, b, n, n, s), n)) +
   ok(pair_eq(Op.cross_ox1(~U32, ~key_u32, a, a, n, n, s), a, a)) : U32)

def sweep_pos(k: Nat, +n: U32, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sweep_pos(p, n, R.step(s), (acc + check_pos(n, s) : U32))

def sweep_ox1(k: Nat, +n: U32, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sweep_ox1(p, n, R.step(s), (acc + check_ox1(n, s) : U32))

# --- OX1 genérico: genes do tipo Char, chave = posição no alfabeto ---
def key_char(c: Char) -> U32:
  (Char.to_u32(c) - 97 : U32)

def char_keys(l: List<&2, Char>) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      Con{key_char(c), char_keys(t)}

def is_alphabet_perm(r: List<&2, Char> & List<&2, Char>) -> Bool:
  (ca, cb) = r
  Bool.and(V.is_permutation(char_keys(ca), 26), V.is_permutation(char_keys(cb), 26))

def alphabet() -> List<&2, Char>:
  String.to_list("abcdefghijklmnopqrstuvwxyz")

def check_char(+s: U32) -> U32:
  +a = V.shuffle(~Char, alphabet(), 26, s)
  +b = V.shuffle(~Char, alphabet(), 26, R.step(s))
  ok(is_alphabet_perm(Op.cross_ox1(~Char, ~key_char, a, b, 26, 26, s)))

def sweep_char(k: Nat, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sweep_char(p, R.step(s), (acc + check_char(s) : U32))

# --- OX1 com mais chaves que genes: linha parcial de sudoku ---
# Os pais são embaralhamentos de {2, 4, 5, 7, 9} (n = 5) com chaves 0..9
# (keys = 10). O filho tem de ser um embaralhamento do MESMO conjunto.
def le(a: U32, b: U32) -> Bool:
  U32.is_le(a, b)

def partial_set() -> List<&2, U32>:
  [2, 4, 5, 7, 9]

def same_set(r: List<&2, U32> & List<&2, U32>, +set: List<&2, U32>) -> Bool:
  (ca, cb) = r
  Bool.and(eq(List.sort(~U32, ~le, ca), set), eq(List.sort(~U32, ~le, cb), set))

def check_partial(+s: U32) -> U32:
  +set = partial_set()
  +a = V.shuffle(~U32, set, 5, s)
  +b = V.shuffle(~U32, set, 5, R.step(s))
  ok(same_set(Op.cross_ox1(~U32, ~key_u32, a, b, 5, 10, s), set))

def sweep_partial(k: Nat, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sweep_partial(p, R.step(s), (acc + check_partial(s) : U32))

def verdict(+name: String, +got: U32, +want: U32) -> String:
  "  " ++ Bool.pick(String, U32.is_eq(got, want), "[OK]     ", "[FALHOU] ") ++
  name ++ ": " ++ U32.show(got) ++ " / " ++ U32.show(want) ++ "\n"

def check_extremes() -> String:
  +a = V.perm_range(8)
  +b = offset(V.perm_range(8), 100)
  verdict("splice com corte n / corte 0 / corte 3",
    (ok(eq(Op.splice(U32, a, b, 8), a)) +
     ok(eq(Op.splice(U32, a, b, 0), b)) +
     ok(eq(Op.splice(U32, a, b, 3), [0, 1, 2, 103, 104, 105, 106, 107])) : U32), 3)

# O exemplo comentado no CrossoverOX1 do Rust, com cortes p1 = 2, p2 = 4:
#   A = [A B C D E F G], B = [F G A B C D E]
#   filho A = [A B C D E F G], filho B = [D E A B C F G]
def rust_b() -> List<&2, U32>:
  [5, 6, 0, 1, 2, 3, 4]

def ox1_rust() -> U32:
  +a = V.perm_range(7)
  +b = rust_b()
  (ok(eq(Op.ox1_fill(~U32, ~key_u32, a, b, 7, 7, 2, 4), [0, 1, 2, 3, 4, 5, 6])) +
   ok(eq(Op.ox1_fill(~U32, ~key_u32, b, a, 7, 7, 2, 4), [3, 4, 0, 1, 2, 5, 6])) : U32)

def main() -> IO(Unit):
  IO.print(
    "=== TESTE DOS CRUZAMENTOS (operators.bend) ===\n" ++
    verdict("posicionais complementares, n = 8, 2000 sementes x 3", sweep_pos(2000n, 8, 13579, 0), 6000) ++
    verdict("posicionais complementares, n = 100000, 5 sementes x 3", sweep_pos(5n, 100000, 24680, 0), 15) ++
    check_extremes() ++
    verdict("OX1: o exemplo do Rust (os dois filhos)", ox1_rust(), 2) ++
    verdict("OX1, n = 12, 2000 sementes x (valido + identidade)", sweep_ox1(2000n, 12, 86427531, 0), 4000) ++
    verdict("OX1, n = 1000, 200 sementes x 2", sweep_ox1(200n, 1000, 111, 0), 400) ++
    verdict("OX1, n = 100000, 5 sementes x 2", sweep_ox1(5n, 100000, 222, 0), 10) ++
    verdict("OX1 com genes Char (chave = letra), 500 sementes", sweep_char(500n, 333, 0), 500) ++
    verdict("OX1 com keys > n (conjunto {2,4,5,7,9}, keys = 10), 1000 sementes", sweep_partial(1000n, 444, 0), 1000)
  )

