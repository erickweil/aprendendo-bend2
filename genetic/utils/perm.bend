import Base

# ================================================================
# BEND 2 GENETIC UTILS - PERMUTATION 8 (perm.bend)
# ================================================================
# Representação imutável de vetor de permutação de 8 elementos.
# Utilizado em problemas combinatórios como TSP, N-Queens e Sorting.
# ================================================================

type Perm8 is Data:
  P8{x0: U32, x1: U32, x2: U32, x3: U32, x4: U32, x5: U32, x6: U32, x7: U32}

def make_perm8(+x0: U32, +x1: U32, +x2: U32, +x3: U32,
               +x4: U32, +x5: U32, +x6: U32, +x7: U32) -> Perm8:
  P8{x0, x1, x2, x3, x4, x5, x6, x7}

def Perm8.get(p: Perm8, +idx: U32) -> U32:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  Bool.pick(U32, U32.is_lt(idx, 4),
    Bool.pick(U32, U32.is_lt(idx, 2),
      Bool.pick(U32, U32.is_eq(idx, 0), x0, x1),
      Bool.pick(U32, U32.is_eq(idx, 2), x2, x3)),
    Bool.pick(U32, U32.is_lt(idx, 6),
      Bool.pick(U32, U32.is_eq(idx, 4), x4, x5),
      Bool.pick(U32, U32.is_eq(idx, 6), x6, x7)))

def Perm8.set(p: Perm8, +idx: U32, +val: U32) -> Perm8:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  P8{
    Bool.pick(U32, U32.is_eq(idx, 0), val, x0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, x1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, x2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, x3),
    Bool.pick(U32, U32.is_eq(idx, 4), val, x4),
    Bool.pick(U32, U32.is_eq(idx, 5), val, x5),
    Bool.pick(U32, U32.is_eq(idx, 6), val, x6),
    Bool.pick(U32, U32.is_eq(idx, 7), val, x7)
  }

def Perm8.swap(+p: Perm8, +i: U32, +j: U32) -> Perm8:
  +vi = Perm8.get(p, i)
  +vj = Perm8.get(p, j)
  +p1 = Perm8.set(p, i, vj)
  Perm8.set(p1, j, vi)

# ----------------------------------------------------------------
# SELETORES LINEARES (evitam avaliação especulativa)
# ----------------------------------------------------------------
# `Bool.pick(Perm8, c, Perm8.swap(p, i, j), p)` faz o CHAMADOR construir
# os dois ramos: o registro de 8 campos é alocado mesmo quando descartado.
# Estes seletores recebem os ingredientes crus e decidem com `match` sobre
# um parâmetro `Bool`, de modo que só o ramo escolhido aloca.
# Medido em laço apertado de 4M iterações: 180ms -> 39ms (4.6x).

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

def Perm8.show(p: Perm8) -> String:
  P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  "[" ++ U32.show(x0) ++ ", " ++ U32.show(x1) ++ ", " ++ U32.show(x2) ++ ", " ++
  U32.show(x3) ++ ", " ++ U32.show(x4) ++ ", " ++ U32.show(x5) ++ ", " ++
  U32.show(x6) ++ ", " ++ U32.show(x7) ++ "]"
