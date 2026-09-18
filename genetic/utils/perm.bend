import Base

# ================================================================
# BEND 2 GENETIC UTILS - PERMUTATION 8 (perm.bend)
# ================================================================
# Permutação imutável de 8 elementos, utilizada em problemas
# combinatórios como TSP, N-Queens e Sorting.
#
# REPRESENTAÇÃO: os 8 elementos (valores 0..7) são empacotados numa
# única palavra de 24 bits, 3 bits cada:
#
#   bits:  [ x7 | x6 | x5 | x4 | x3 | x2 | x1 | x0 ]
#           23               ...              5  2  0
#
# O registro de 8 campos anterior alocava um nó de heap por operação;
# `swap` sozinho construía dois. Empacotado, o genoma inteiro cabe numa
# palavra, e o construtor de 1 campo não paga nada por isso: medido em
# laço de 4M swaps, 28ms -> 15ms (1,9x), exatamente o tempo de um U32
# cru. Como o motor aloca um genoma por indivíduo por geração, isso
# também reduz o tráfego na heap compartilhada, que é o que limita a
# escala multicore (ver PERFORMANCE.md).
#
# O tipo continua distinto de U32, então nenhuma aritmética solta pode
# ser confundida com uma permutação.
# ================================================================

type Perm8 is Data:
  P8{bits: U32}

# Deslocamento do elemento `idx` dentro da palavra.
# O índice é mascarado em [0, 7], então `get` e `set` são totais.
def Perm8.shift(+idx: U32) -> Nat:
  U32.to_nat(U32.mul(U32.and(idx, 7), 3))

# Palavra empacotada crua (para hashing, comparação ou depuração)
def Perm8.bits(p: Perm8) -> U32:
  P8{b} = p
  b

def make_perm8(+x0: U32, +x1: U32, +x2: U32, +x3: U32,
               +x4: U32, +x5: U32, +x6: U32, +x7: U32) -> Perm8:
  P8{
    U32.or(U32.and(x0, 7),
      U32.or(U32.shln(U32.and(x1, 7), 3n),
        U32.or(U32.shln(U32.and(x2, 7), 6n),
          U32.or(U32.shln(U32.and(x3, 7), 9n),
            U32.or(U32.shln(U32.and(x4, 7), 12n),
              U32.or(U32.shln(U32.and(x5, 7), 15n),
                U32.or(U32.shln(U32.and(x6, 7), 18n),
                       U32.shln(U32.and(x7, 7), 21n))))))))
  }

# Permutação identidade [0, 1, 2, 3, 4, 5, 6, 7]
def Perm8.identity() -> Perm8:
  P8{16434824}

def Perm8.get(p: Perm8, +idx: U32) -> U32:
  P8{b} = p
  U32.and(U32.shrn(b, Perm8.shift(idx)), 7)

def Perm8.set(p: Perm8, +idx: U32, +val: U32) -> Perm8:
  P8{b} = p
  +sh = Perm8.shift(idx)
  +sh = sh
  P8{U32.or(U32.and(b, U32.not(U32.shln(7, sh))), U32.shln(U32.and(val, 7), sh))}

def Perm8.swap(+p: Perm8, +i: U32, +j: U32) -> Perm8:
  P8{b} = p
  +b = b
  +shi = Perm8.shift(i)
  +shj = Perm8.shift(j)
  +shi = shi; +shj = shj
  +vi = U32.and(U32.shrn(b, shi), 7)
  +vj = U32.and(U32.shrn(b, shj), 7)
  +diff = U32.xor(vi, vj)
  +diff = diff
  +mask = U32.or(U32.shln(diff, shi), U32.shln(diff, shj))
  P8{U32.xor(b, mask)}

# Posição do valor `val` na permutação (0..7; devolve 7 se ausente)
def Perm8.index_of(+p: Perm8, +val: U32) -> U32:
  Bool.pick(U32, U32.is_eq(Perm8.get(p, 0), val), 0,
    Bool.pick(U32, U32.is_eq(Perm8.get(p, 1), val), 1,
      Bool.pick(U32, U32.is_eq(Perm8.get(p, 2), val), 2,
        Bool.pick(U32, U32.is_eq(Perm8.get(p, 3), val), 3,
          Bool.pick(U32, U32.is_eq(Perm8.get(p, 4), val), 4,
            Bool.pick(U32, U32.is_eq(Perm8.get(p, 5), val), 5,
              Bool.pick(U32, U32.is_eq(Perm8.get(p, 6), val), 6, 7)))))))

# ----------------------------------------------------------------
# SELETORES LINEARES (evitam avaliação especulativa)
# ----------------------------------------------------------------
# `Bool.pick(Perm8, c, Perm8.swap(p, i, j), p)` faz o CHAMADOR construir
# os dois ramos. Estes seletores recebem os ingredientes crus e decidem
# com `match` sobre um parâmetro `Bool`, então só o ramo escolhido roda.
# Ver PERFORMANCE.md §2.

def Perm8.swap_if(cond: Bool, p: Perm8, +i: U32, +j: U32) -> Perm8:
  match cond:
    case True{}:
      Perm8.swap(p, i, j)
    case False{}:
      p

def Perm8.set_if(cond: Bool, p: Perm8, +idx: U32, +val: U32) -> Perm8:
  match cond:
    case True{}:
      Perm8.set(p, idx, val)
    case False{}:
      p

def Perm8.show(+p: Perm8) -> String:
  "[" ++ U32.show(Perm8.get(p, 0)) ++ ", " ++ U32.show(Perm8.get(p, 1)) ++ ", " ++
         U32.show(Perm8.get(p, 2)) ++ ", " ++ U32.show(Perm8.get(p, 3)) ++ ", " ++
         U32.show(Perm8.get(p, 4)) ++ ", " ++ U32.show(Perm8.get(p, 5)) ++ ", " ++
         U32.show(Perm8.get(p, 6)) ++ ", " ++ U32.show(Perm8.get(p, 7)) ++ "]"
