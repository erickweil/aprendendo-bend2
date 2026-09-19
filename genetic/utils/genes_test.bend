import Base
import ./../../utils/random.bend as R
import ./genes.bend as V

# ================================================================
# TESTE DE genes.bend (núcleo do vetor de genes)
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

def check(+name: String, ok: Bool) -> String:
  Bool.pick(String, ok, "  [OK]     " ++ name ++ "\n", "  [FALHOU] " ++ name ++ "\n")

def base() -> List<&2, U32>:
  [10, 20, 30, 40, 50]

# Ida e volta lista -> Array -> lista, para um tamanho qualquer (inclusive
# não potência de 2, que obriga o array a ter posições excedentes)
def roundtrip(+n: U32) -> Bool:
  +l = V.perm_range(n)
  eq(V.from_array(~U32, V.to_array(~U32, l, n, 0), n), l)

def main() -> IO(Unit):
  IO.print(
    "=== genes.bend ===\n" ++
    check("len", U32.is_eq(V.len(U32, base()), 5)) ++
    check("nth(0) / nth(4)", Bool.and(U32.is_eq(V.nth(U32, base(), 0, 999), 10), U32.is_eq(V.nth(U32, base(), 4, 999), 50))) ++
    check("nth fora do intervalo devolve o default", U32.is_eq(V.nth(U32, base(), 9, 999), 999)) ++
    check("set_at(2)", eq(V.set_at(U32, base(), 2, 77), [10, 20, 77, 40, 50])) ++
    check("take(2) / take(0) / take(99)", Bool.and(eq(V.take(U32, base(), 2), [10, 20]),
      Bool.and(eq(V.take(U32, base(), 0), []), eq(V.take(U32, base(), 99), base())))) ++
    check("drop(2) / drop(0) / drop(99)", Bool.and(eq(V.drop(U32, base(), 2), [30, 40, 50]),
      Bool.and(eq(V.drop(U32, base(), 0), base()), eq(V.drop(U32, base(), 99), [])))) ++
    check("take ++ drop reconstroi", eq(V.append(U32, V.take(U32, base(), 3), V.drop(U32, base(), 3)), base())) ++
    check("rotate(2) / rotate(0)", Bool.and(eq(V.rotate(U32, base(), 2), [30, 40, 50, 10, 20]), eq(V.rotate(U32, base(), 0), base()))) ++
    check("swap_at(0,4) / swap_at(2,2)", Bool.and(eq(V.swap_at(U32, base(), 0, 4, 999), [50, 20, 30, 40, 10]), eq(V.swap_at(U32, base(), 2, 2, 999), base()))) ++
    check("depth_for(1,2,12,16,17,1M)", Bool.and(U32.is_eq(U32.from_nat(V.depth_for(1)), 0),
      Bool.and(U32.is_eq(U32.from_nat(V.depth_for(2)), 1),
      Bool.and(U32.is_eq(U32.from_nat(V.depth_for(12)), 4),
      Bool.and(U32.is_eq(U32.from_nat(V.depth_for(16)), 4),
      Bool.and(U32.is_eq(U32.from_nat(V.depth_for(17)), 5), U32.is_eq(U32.from_nat(V.depth_for(1000000)), 20))))))) ++
    check("lista -> Array -> lista (n = 1, 12, 1000, 100000)", Bool.and(roundtrip(1),
      Bool.and(roundtrip(12), Bool.and(roundtrip(1000), roundtrip(100000))))) ++
    check("is_permutation aceita identidade e embaralhamento (n = 100000)",
      Bool.and(V.is_permutation(V.perm_range(100000), 100000),
               V.is_permutation(V.perm_random(100000, 42), 100000))) ++
    check("perm_random embaralha de fato (n = 1000)", Bool.not(eq(V.perm_random(1000, 7), V.perm_range(1000)))) ++
    check("is_permutation rejeita repetido, fora do intervalo e tamanho errado",
      Bool.and(Bool.not(V.is_permutation([0, 1, 1, 3], 4)),
      Bool.and(Bool.not(V.is_permutation([0, 1, 2, 7], 4)), Bool.not(V.is_permutation([0, 1, 2], 4)))))
  )
