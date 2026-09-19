import Base
import ./../../utils/random.bend as R
import ./genes.bend as G

# ================================================================
# TESTE DE genes.bend
# ================================================================

def show(l: List<&2, U32>) -> String:
  match l:
    case Nil{}:
      ""
    case Con{h, t}:
      U32.show(h) ++ "," ++ show(t)

def eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Nil{} Con{y, ys}:
      False{}
    case Con{x, xs} Nil{}:
      False{}
    case Con{x, xs} Con{y, ys}:
      Bool.pick(Bool, U32.is_eq(x, y), eq(xs, ys), False{})

def check(+name: String, ok: Bool) -> String:
  Bool.pick(String, ok, "  [OK]   " ++ name ++ "\n", "  [FALHOU] " ++ name ++ "\n")

def base() -> List<&2, U32>:
  [10, 20, 30, 40, 50]

# ----------------------------------------------------------------
# CRUZAMENTOS: todo gene do filho vem de um dos pais, na mesma posição
# ----------------------------------------------------------------
def from_parents(c: List<&2, U32>, a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match c a b:
    case Nil{} Nil{} Nil{}:
      True{}
    case Nil{} Nil{} Con{y, ys}:
      False{}
    case Nil{} Con{x, xs} Nil{}:
      False{}
    case Nil{} Con{x, xs} Con{y, ys}:
      False{}
    case Con{z, zs} Nil{} Nil{}:
      False{}
    case Con{z, zs} Nil{} Con{y, ys}:
      False{}
    case Con{z, zs} Con{x, xs} Nil{}:
      False{}
    case Con{z, zs} Con{x, xs} Con{y, ys}:
      +z = z
      Bool.pick(Bool, Bool.or(U32.is_eq(z, x), U32.is_eq(z, y)),
        from_parents(zs, xs, ys), False{})

def pa() -> List<&2, U32>:
  [1, 2, 3, 4, 5, 6, 7, 8]

def pb() -> List<&2, U32>:
  [101, 102, 103, 104, 105, 106, 107, 108]

# Uma semente falha se qualquer cruzamento produzir gene que não veio de pai,
# ou comprimento diferente de 8
def check_cross(+s: U32) -> U32:
  +cu = G.cross_uniform(U32, pa(), pb(), s)
  +c1 = G.cross_1point(U32, pa(), pb(), 8, s)
  +c2 = G.cross_2point(U32, pa(), pb(), 8, s)
  +ok_len = Bool.and(U32.is_eq(G.len(U32, cu), 8),
            Bool.and(U32.is_eq(G.len(U32, c1), 8), U32.is_eq(G.len(U32, c2), 8)))
  +ok_src = Bool.and(from_parents(cu, pa(), pb()),
            Bool.and(from_parents(c1, pa(), pb()), from_parents(c2, pa(), pb())))
  Bool.pick(U32, Bool.and(ok_len, ok_src), 1, 0)

def sweep(n: Nat, +s: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+q:
      +s = s
      sweep(q, R.step(s), (acc + check_cross(s) : U32))

# ----------------------------------------------------------------
# PERMUTAÇÕES: OX1 e as mutações de troca preservam a permutação
# ----------------------------------------------------------------
def perm_a() -> List<&2, U32>:
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

def perm_b(+s: U32) -> List<&2, U32>:
  G.perm_shuffle(24n, perm_a(), 12, s)

# Se os dois pais são iguais, OX1 tem de devolver exatamente esse pai:
# o segmento vem dele e os faltantes aparecem em `b` na mesma ordem.
def check_ox1_identity(+s: U32) -> U32:
  +p = perm_b(s)
  +p = p
  Bool.pick(U32, eq(G.cross_ox1(p, p, 12, s), perm_b(s)), 1, 0)

def sweep_ox1_id(n: Nat, +s: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+q:
      +s = s
      sweep_ox1_id(q, R.step(s), (acc + check_ox1_identity(s) : U32))

def check_perm(+s: U32) -> U32:
  +pb = perm_b(s)
  +pb = pb
  # OX1 entre a identidade e um embaralhamento
  +child = G.cross_ox1(perm_a(), pb, 12, s)
  # mutações de troca sobre o filho
  +m1 = G.mut_swap(U32, child, 100, 12, s, 0)
  +m2 = G.mut_neighbor(U32, perm_b(s), 50, s)
  +ok = Bool.and(G.is_permutation(pb, 12),
        Bool.and(G.is_permutation(G.cross_ox1(perm_a(), perm_b(s), 12, s), 12),
        Bool.and(G.is_permutation(m1, 12), G.is_permutation(m2, 12))))
  Bool.pick(U32, ok, 1, 0)

def sweep_perm(n: Nat, +s: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+q:
      +s = s
      sweep_perm(q, R.step(s), (acc + check_perm(s) : U32))

def verdict(+got: U32, +want: U32) -> String:
  U32.show(got) ++ " / " ++ U32.show(want) ++
  Bool.pick(String, U32.is_eq(got, want), "  [OK]", "  [FALHOU]")

def main() -> IO(Unit):
  IO.print(
    "=== genes.bend ===\n" ++
    check("len", U32.is_eq(G.len(U32, base()), 5)) ++
    check("nth(0)", U32.is_eq(G.nth(U32, base(), 0, 999), 10)) ++
    check("nth(4)", U32.is_eq(G.nth(U32, base(), 4, 999), 50)) ++
    check("nth fora do intervalo devolve o default", U32.is_eq(G.nth(U32, base(), 9, 999), 999)) ++
    check("set_at(2)", eq(G.set_at(U32, base(), 2, 77), [10, 20, 77, 40, 50])) ++
    check("take(2)", eq(G.take(U32, base(), 2), [10, 20])) ++
    check("take(0)", eq(G.take(U32, base(), 0), [])) ++
    check("take(99) satura", eq(G.take(U32, base(), 99), base())) ++
    check("drop(2)", eq(G.drop(U32, base(), 2), [30, 40, 50])) ++
    check("drop(0)", eq(G.drop(U32, base(), 0), base())) ++
    check("drop(99) esvazia", eq(G.drop(U32, base(), 99), [])) ++
    check("append", eq(G.append(U32, [1, 2], [3]), [1, 2, 3])) ++
    check("take ++ drop reconstroi", eq(G.append(U32, G.take(U32, base(), 3), G.drop(U32, base(), 3)), base())) ++
    check("rotate(2)", eq(G.rotate(U32, base(), 2), [30, 40, 50, 10, 20])) ++
    check("rotate(0) e identidade", eq(G.rotate(U32, base(), 0), base())) ++
    check("swap_at(0,4)", eq(G.swap_at(U32, base(), 0, 4, 999), [50, 20, 30, 40, 10])) ++
    check("swap_at(i,i) e identidade", eq(G.swap_at(U32, base(), 2, 2, 999), base())) ++
    check("cross_1point mantem prefixo de A quando o corte e 8", eq(G.cross(~G.pred_1point, U32, pa(), pb(), 8, 0), pa())) ++
    check("cross_1point vira B inteiro quando o corte e 0", eq(G.cross(~G.pred_1point, U32, pa(), pb(), 0, 0), pb())) ++
    "\nCruzamentos x 2000 sementes (origem dos genes + comprimento): " ++
    verdict(sweep(2000n, 24681357, 0), 2000) ++ "\n" ++
    "Permutacoes x 2000 sementes (OX1 + mut_swap + mut_neighbor + shuffle): " ++
    verdict(sweep_perm(2000n, 86427531, 0), 2000) ++ "\n" ++
    "OX1 com pais iguais devolve o pai x 2000 sementes: " ++
    verdict(sweep_ox1_id(2000n, 19283746, 0), 2000) ++ "\n"
  )
