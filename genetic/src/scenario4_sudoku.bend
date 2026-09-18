import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R

type Row9 is Data:
  R9{x0: U32, x1: U32, x2: U32, x3: U32, x4: U32, x5: U32, x6: U32, x7: U32, x8: U32}

type Sudoku9 is Data:
  S9{
    r0: Row9, r1: Row9, r2: Row9,
    r3: Row9, r4: Row9, r5: Row9,
    r6: Row9, r7: Row9, r8: Row9
  }

# Xorshift32 PRNG
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

def Row9.get(r: Row9, +idx: U32) -> U32:
  R9{x0, x1, x2, x3, x4, x5, x6, x7, x8} = r
  Bool.pick(U32, U32.is_lt(idx, 4),
    Bool.pick(U32, U32.is_lt(idx, 2),
      Bool.pick(U32, U32.is_eq(idx, 0), x0, x1),
      Bool.pick(U32, U32.is_eq(idx, 2), x2, x3)),
    Bool.pick(U32, U32.is_lt(idx, 7),
      Bool.pick(U32, U32.is_eq(idx, 4), x4,
        Bool.pick(U32, U32.is_eq(idx, 5), x5, x6)),
      Bool.pick(U32, U32.is_eq(idx, 7), x7, x8)))

def Row9.set(r: Row9, +idx: U32, +val: U32) -> Row9:
  R9{x0, x1, x2, x3, x4, x5, x6, x7, x8} = r
  R9{
    Bool.pick(U32, U32.is_eq(idx, 0), val, x0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, x1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, x2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, x3),
    Bool.pick(U32, U32.is_eq(idx, 4), val, x4),
    Bool.pick(U32, U32.is_eq(idx, 5), val, x5),
    Bool.pick(U32, U32.is_eq(idx, 6), val, x6),
    Bool.pick(U32, U32.is_eq(idx, 7), val, x7),
    Bool.pick(U32, U32.is_eq(idx, 8), val, x8)
  }

def Row9.swap(+r: Row9, +i: U32, +j: U32) -> Row9:
  +vi = Row9.get(r, i)
  +vj = Row9.get(r, j)
  +r1 = Row9.set(r, i, vj)
  Row9.set(r1, j, vi)

def Sudoku9.get_row(s: Sudoku9, +r: U32) -> Row9:
  S9{r0, r1, r2, r3, r4, r5, r6, r7, r8} = s
  Bool.pick(Row9, U32.is_lt(r, 4),
    Bool.pick(Row9, U32.is_lt(r, 2),
      Bool.pick(Row9, U32.is_eq(r, 0), r0, r1),
      Bool.pick(Row9, U32.is_eq(r, 2), r2, r3)),
    Bool.pick(Row9, U32.is_lt(r, 7),
      Bool.pick(Row9, U32.is_eq(r, 4), r4,
        Bool.pick(Row9, U32.is_eq(r, 5), r5, r6)),
      Bool.pick(Row9, U32.is_eq(r, 7), r7, r8)))

def Sudoku9.set_row(s: Sudoku9, +r: U32, +row: Row9) -> Sudoku9:
  S9{r0, r1, r2, r3, r4, r5, r6, r7, r8} = s
  S9{
    Bool.pick(Row9, U32.is_eq(r, 0), row, r0),
    Bool.pick(Row9, U32.is_eq(r, 1), row, r1),
    Bool.pick(Row9, U32.is_eq(r, 2), row, r2),
    Bool.pick(Row9, U32.is_eq(r, 3), row, r3),
    Bool.pick(Row9, U32.is_eq(r, 4), row, r4),
    Bool.pick(Row9, U32.is_eq(r, 5), row, r5),
    Bool.pick(Row9, U32.is_eq(r, 6), row, r6),
    Bool.pick(Row9, U32.is_eq(r, 7), row, r7),
    Bool.pick(Row9, U32.is_eq(r, 8), row, r8)
  }

def Sudoku9.swap_cell(+s: Sudoku9, +r: U32, +i: U32, +j: U32) -> Sudoku9:
  +row = Sudoku9.get_row(s, r)
  +swapped = Row9.swap(row, i, j)
  Sudoku9.set_row(s, r, swapped)

def Sudoku9.swap_rows(+s: Sudoku9, +r1: U32, +r2: U32) -> Sudoku9:
  +row1 = Sudoku9.get_row(s, r1)
  +row2 = Sudoku9.get_row(s, r2)
  +s1 = Sudoku9.set_row(s, r1, row2)
  Sudoku9.set_row(s1, r2, row1)

def Sudoku9.swap_cols(+s: Sudoku9, +c1: U32, +c2: U32) -> Sudoku9:
  S9{r0, r1, r2, r3, r4, r5, r6, r7, r8} = s
  S9{
    Row9.swap(r0, c1, c2),
    Row9.swap(r1, c1, c2),
    Row9.swap(r2, c1, c2),
    Row9.swap(r3, c1, c2),
    Row9.swap(r4, c1, c2),
    Row9.swap(r5, c1, c2),
    Row9.swap(r6, c1, c2),
    Row9.swap(r7, c1, c2),
    Row9.swap(r8, c1, c2)
  }

def bit_of(+d: U32) -> U32:
  U32.shln(1, U32.to_nat(d))

def popcount.word(n: Nat, w: Word(n)) -> U32:
  match n w:
    case 0n WNil{}:
      0
    case 1n+p WCon{b, tail}:
      match b:
        case True{}:
          U32.inc(popcount.word(p, tail))
        case False{}:
          popcount.word(p, tail)

def popcount(u: U32) -> U32:
  match u:
    case U32{w}:
      popcount.word(32n, w)

def group_unique(
  +c0: U32, +c1: U32, +c2: U32,
  +c3: U32, +c4: U32, +c5: U32,
  +c6: U32, +c7: U32, +c8: U32
) -> U32:
  +m0 = bit_of(c0); +m1 = bit_of(c1); +m2 = bit_of(c2)
  +m3 = bit_of(c3); +m4 = bit_of(c4); +m5 = bit_of(c5)
  +m6 = bit_of(c6); +m7 = bit_of(c7); +m8 = bit_of(c8)
  +mask = U32.or(m0, U32.or(m1, U32.or(m2, U32.or(m3, U32.or(m4, U32.or(m5, U32.or(m6, U32.or(m7, m8))))))))
  popcount(mask)

def eval_sudoku9(s: Sudoku9) -> U32:
  S9{
    R9{a0, a1, a2, a3, a4, a5, a6, a7, a8},
    R9{b0, b1, b2, b3, b4, b5, b6, b7, b8},
    R9{c0, c1, c2, c3, c4, c5, c6, c7, c8},
    R9{d0, d1, d2, d3, d4, d5, d6, d7, d8},
    R9{e0, e1, e2, e3, e4, e5, e6, e7, e8},
    R9{f0, f1, f2, f3, f4, f5, f6, f7, f8},
    R9{g0, g1, g2, g3, g4, g5, g6, g7, g8},
    R9{h0, h1, h2, h3, h4, h5, h6, h7, h8},
    R9{i0, i1, i2, i3, i4, i5, i6, i7, i8}
  } = s
  +a0 = a0; +a1 = a1; +a2 = a2; +a3 = a3; +a4 = a4; +a5 = a5; +a6 = a6; +a7 = a7; +a8 = a8
  +b0 = b0; +b1 = b1; +b2 = b2; +b3 = b3; +b4 = b4; +b5 = b5; +b6 = b6; +b7 = b7; +b8 = b8
  +c0 = c0; +c1 = c1; +c2 = c2; +c3 = c3; +c4 = c4; +c5 = c5; +c6 = c6; +c7 = c7; +c8 = c8
  +d0 = d0; +d1 = d1; +d2 = d2; +d3 = d3; +d4 = d4; +d5 = d5; +d6 = d6; +d7 = d7; +d8 = d8
  +e0 = e0; +e1 = e1; +e2 = e2; +e3 = e3; +e4 = e4; +e5 = e5; +e6 = e6; +e7 = e7; +e8 = e8
  +f0 = f0; +f1 = f1; +f2 = f2; +f3 = f3; +f4 = f4; +f5 = f5; +f6 = f6; +f7 = f7; +f8 = f8
  +g0 = g0; +g1 = g1; +g2 = g2; +g3 = g3; +g4 = g4; +g5 = g5; +g6 = g6; +g7 = g7; +g8 = g8
  +h0 = h0; +h1 = h1; +h2 = h2; +h3 = h3; +h4 = h4; +h5 = h5; +h6 = h6; +h7 = h7; +h8 = h8
  +i0 = i0; +i1 = i1; +i2 = i2; +i3 = i3; +i4 = i4; +i5 = i5; +i6 = i6; +i7 = i7; +i8 = i8

  # 9 Columns
  +col0 = group_unique(a0, b0, c0, d0, e0, f0, g0, h0, i0)
  +col1 = group_unique(a1, b1, c1, d1, e1, f1, g1, h1, i1)
  +col2 = group_unique(a2, b2, c2, d2, e2, f2, g2, h2, i2)
  +col3 = group_unique(a3, b3, c3, d3, e3, f3, g3, h3, i3)
  +col4 = group_unique(a4, b4, c4, d4, e4, f4, g4, h4, i4)
  +col5 = group_unique(a5, b5, c5, d5, e5, f5, g5, h5, i5)
  +col6 = group_unique(a6, b6, c6, d6, e6, f6, g6, h6, i6)
  +col7 = group_unique(a7, b7, c7, d7, e7, f7, g7, h7, i7)
  +col8 = group_unique(a8, b8, c8, d8, e8, f8, g8, h8, i8)
  +total_cols = (col0 + col1 + col2 + col3 + col4 + col5 + col6 + col7 + col8 : U32)

  # 9 Boxes (3x3)
  +box0 = group_unique(a0, a1, a2, b0, b1, b2, c0, c1, c2)
  +box1 = group_unique(a3, a4, a5, b3, b4, b5, c3, c4, c5)
  +box2 = group_unique(a6, a7, a8, b6, b7, b8, c6, c7, c8)

  +box3 = group_unique(d0, d1, d2, e0, e1, e2, f0, f1, f2)
  +box4 = group_unique(d3, d4, d5, e3, e4, e5, f3, f4, f5)
  +box5 = group_unique(d6, d7, d8, e6, e7, e8, f6, f7, f8)

  +box6 = group_unique(g0, g1, g2, h0, h1, h2, i0, i1, i2)
  +box7 = group_unique(g3, g4, g5, h3, h4, h5, i3, i4, i5)
  +box8 = group_unique(g6, g7, g8, h6, h7, h8, i6, i7, i8)
  +total_boxes = (box0 + box1 + box2 + box3 + box4 + box5 + box6 + box7 + box8 : U32)

  (total_cols + total_boxes : U32)

def fitness(s: Sudoku9) -> U32:
  eval_sudoku9(s)

type Ind is Data:
  Ind{gene: Sudoku9, fit: U32}

def Ind.gene(ind: Ind) -> Sudoku9:
  Ind{g, _} = ind
  g

def Ind.fit(ind: Ind) -> U32:
  Ind{_, f} = ind
  f

type PopTree is Data:
  Leaf{ind: Ind}
  Node{left: PopTree, right: PopTree}

def eval_pop(tree: PopTree) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      +gene = g
      Leaf{Ind{gene, fitness(gene)}}
    case Node{left, right}:
      l r = eval_pop(left) eval_pop(right)
      Node{l, r}

def pick_better(+a: Ind, +b: Ind) -> Ind:
  +fa = Ind.fit(a)
  +fb = Ind.fit(b)
  Bool.pick(Ind, U32.is_ge(fa, fb), a, b)

def best_pop(tree: PopTree) -> Ind:
  match tree:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      bl br = best_pop(left) best_pop(right)
      pick_better(bl, br)

# Quadro completamente vazio (81 zeros)
def empty_row() -> Row9:
  R9{0, 0, 0, 0, 0, 0, 0, 0, 0}

def quadro_vazio() -> Sudoku9:
  +r0 = empty_row()
  S9{r0, r0, r0, r0, r0, r0, r0, r0, r0}

def base_row() -> Row9:
  R9{1, 2, 3, 4, 5, 6, 7, 8, 9}

def row_shift_3(r: Row9) -> Row9:
  R9{x0, x1, x2, x3, x4, x5, x6, x7, x8} = r
  R9{x3, x4, x5, x6, x7, x8, x0, x1, x2}

def row_shift_1(r: Row9) -> Row9:
  R9{x0, x1, x2, x3, x4, x5, x6, x7, x8} = r
  R9{x1, x2, x3, x4, x5, x6, x7, x8, x0}

def make_initial_grid(
  r0: Row9, r1: Row9, r2: Row9,
  r3: Row9, r4: Row9, r5: Row9,
  r6: Row9, r7: Row9, r8: Row9
) -> Sudoku9:
  S9{r0, r1, r2, r3, r4, r5, r6, r7, r8}

# Preenche o quadro vazio gerando um estado de busca aleatório
def preencher_a_partir_de_vazio(+vazio: Sudoku9, +s: U32) -> Sudoku9:
  # Inicia com as 9 linhas preenchidas com permutação base
  +r0 = base_row()
  +r1 = row_shift_3(r0)
  +r2 = row_shift_3(r1)
  +r3 = row_shift_1(r0)
  +r4 = row_shift_3(r3)
  +r5 = row_shift_3(r4)
  +r6 = row_shift_1(r3)
  +r7 = row_shift_3(r6)
  +r8 = row_shift_3(r7)
  +grid = make_initial_grid(r0, r1, r2, r3, r4, r5, r6, r7, r8)
  # Embaralha com operações válidas de Sudoku
  +s1 = step(s); +s2 = step(s1); +s3 = step(s2); +s4 = step(s3)
  +g1 = Sudoku9.swap_rows(grid, U32.mod(s1, 3), U32.mod(s2, 3))
  +g2 = Sudoku9.swap_cols(g1, U32.mod(s3, 3), U32.mod(s4, 3))
  +s5 = step(s4); +s6 = step(s5); +s7 = step(s6); +s8 = step(s7)
  +g3 = Sudoku9.swap_rows(g2, (3 + U32.mod(s5, 3) : U32), (3 + U32.mod(s6, 3) : U32))
  Sudoku9.swap_cols(g3, (3 + U32.mod(s7, 3) : U32), (3 + U32.mod(s8, 3) : U32))
def init_gene(seed: U32) -> Sudoku9:
  preencher_a_partir_de_vazio(quadro_vazio(), seed)

# Despacho linear da vizinhança: cada um dos três operadores reconstrói uma
# grade 9x9 inteira. Como argumentos de `Bool.pick` as três grades eram
# construídas a cada mutação e duas descartadas.
def sudoku_neighborhood(is_rows: Bool, is_cols: Bool, +s: Sudoku9,
                        +o1: U32, +o2: U32, +r: U32, +c: U32) -> Sudoku9:
  match is_rows:
    case True{}:
      Sudoku9.swap_rows(s, o1, o2)
    case False{}:
      match is_cols:
        case True{}:
          Sudoku9.swap_cols(s, o1, o2)
        case False{}:
          Sudoku9.swap_cell(s, o1, r, c)

def mutate_sudoku9(+s: Sudoku9, +rnd: U32) -> Sudoku9:
  +s1 = R.step(rnd); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +s3 = s3; +s4 = s4
  +mode = U32.mod(s1, 3)
  +mode = mode
  +band = U32.mul(U32.mod(s2, 3), 3)
  +o1 = (band + U32.mod(s3, 3) : U32)
  +o2 = (band + U32.mod(s4, 3) : U32)
  sudoku_neighborhood(U32.is_eq(mode, 0), U32.is_eq(mode, 1), s, o1, o2,
                      U32.mod(s3, 9), U32.mod(s4, 9))

def pick_better_sudoku(c: Bool, cand: Sudoku9, +f_cand: U32, base: Sudoku9, +f_base: U32) -> GA.Ind<Sudoku9>:
  match c:
    case True{}:
      GA.Ind{cand, f_cand}
    case False{}:
      GA.Ind{base, f_base}

def memetic_improve_eval(+s: Sudoku9, +rnd: U32) -> GA.Ind<Sudoku9>:
  +cand = mutate_sudoku9(s, rnd)
  +f_old = fitness(s)
  +f_new = fitness(cand)
  pick_better_sudoku(U32.is_ge(f_new, f_old), cand, f_new, s, f_old)

def reproduce_eval(parent: Sudoku9, champ: Sudoku9, seed: U32) -> GA.Ind<Sudoku9>:
  +s1 = R.step(seed)
  +s2 = R.step(s1)
  +base = Bool.pick(Sudoku9, U32.is_lt(U32.mod(s1, 10), 6), champ, parent)
  memetic_improve_eval(base, s2)

def reproduce(parent: Sudoku9, champ: Sudoku9, seed: U32) -> Sudoku9:
  GA.Ind.gene(Sudoku9, reproduce_eval(parent, champ, seed))

def Row9.show(r: Row9) -> String:
  R9{x0, x1, x2, x3, x4, x5, x6, x7, x8} = r
  "[" ++ U32.show(x0) ++ " " ++ U32.show(x1) ++ " " ++ U32.show(x2) ++ " | " ++
         U32.show(x3) ++ " " ++ U32.show(x4) ++ " " ++ U32.show(x5) ++ " | " ++
         U32.show(x6) ++ " " ++ U32.show(x7) ++ " " ++ U32.show(x8) ++ "]"

def Sudoku9.show(s: Sudoku9) -> String:
  S9{r0, r1, r2, r3, r4, r5, r6, r7, r8} = s
  "\n" ++ Row9.show(r0) ++ "\n" ++ Row9.show(r1) ++ "\n" ++ Row9.show(r2) ++ "\n" ++
  "------+-------+------\n" ++
  Row9.show(r3) ++ "\n" ++ Row9.show(r4) ++ "\n" ++ Row9.show(r5) ++ "\n" ++
  "------+-------+------\n" ++
  Row9.show(r6) ++ "\n" ++ Row9.show(r7) ++ "\n" ++ Row9.show(r8) ++ "\n"

def main_seed() -> U32:
  778899

def main() -> IO(Unit):
  +s0 = main_seed()
  +pop0 = GA.gen_population(~Sudoku9, ~init_gene, ~fitness, 5n, s0)
  +best0 = GA.best_ind(Sudoku9, pop0)
  +f0 = GA.Ind.fit(Sudoku9, best0)

  # 30 gerações com o motor genérico avaliado (elimina a 3ª avaliação de colunas/blocos)
  +pop_final = GA.run_generations_eval(~Sudoku9, ~reproduce_eval, 30n, pop0, R.step(s0))
  +best_fin = GA.best_ind(Sudoku9, pop_final)
  +g_fin = GA.Ind.gene(Sudoku9, best_fin)
  +f_fin = GA.Ind.fit(Sudoku9, best_fin)
  +c_fin = (162 - f_fin : U32)

  IO.print(
    "=== CENÁRIO 4: SUDOKU 9x9 A PARTIR DE QUADRO VAZIO ===\n" ++
    "Início: Quadro vazio (81 zeros), preenchido e evoluído dinamicamente\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Métrica: 9 Linhas x 9 Colunas x 9 Blocos (Ótimo = 162, 0 conflitos)\n" ++
    "Geração Final - Conflitos: " ++ U32.show(c_fin) ++ " (Fitness: " ++ U32.show(f_fin) ++ " / 162)" ++ Sudoku9.show(g_fin) ++ "\n" ++
    "Sudoku 9x9 Resolvido com Sucesso (0 conflitos)? " ++ Bool.show(U32.is_zero(c_fin)) ++ "\n"
  )
