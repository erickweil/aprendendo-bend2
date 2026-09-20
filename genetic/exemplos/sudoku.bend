import Base
import ./../arena.bend as A
import ./../operators.bend as Op
import ./../ga.bend as GA
import ./../../utils/arrays.bend as Arr
import ./../../utils/random.bend as R
import ./../../utils/math.bend as Math
import ./../../utils/io.bend as IOU

# ================================================================
# SUDOKU (sudoku.bend) — Resolução de Sudoku via Algoritmo Genético
# ================================================================
# Problema: preencher um quadro 9x9 inicialmente vazio de modo que cada
# linha, coluna e caixa 3x3 contenha todos os dígitos 1..9 sem repetição.
#
# Representação do Genoma:
#   Array<U32> de 128 elementos (profundidade 7), onde os índices 0..80
#   guardam as 81 células: célula (r, c) fica no índice (r * 9 + c).
#
# Estratégia Row-Permutation:
#   Cada linha é SEMPRE uma permutação válida de [1..9].
#   Portanto, as 9 linhas têm sempre pontuação máxima (81 pontos).
#   O algoritmo busca satisfazer as 9 colunas e as 9 caixas 3x3.
#
# Aptidão (Fitness):
#   - 9 linhas: 81 pontos (garantidos pela representação)
#   - 9 colunas: quantidade de dígitos distintos em cada coluna (até 81)
#   - 9 caixas 3x3: quantidade de dígitos distintos em cada caixa (até 81)
#   Aptidão Máxima: 81 + 81 + 81 = 243 pontos (ÓTIMO / RESOLVIDO).
#
# Crossover:
#   Order Crossover (OX1) por linha via `Op.breed_ox1_slice`.
#   Preserva estritamente a permutação em cada linha.
#
# Mutação:
#   Troca aleatória de dois dígitos dentro da mesma linha (`mut_one`).
#   Preserva estritamente a permutação em cada linha.
# ================================================================

type Sudoku is Data:
  Sudoku{max_fit: U32}

def sudoku_new() -> Sudoku:
  Sudoku{243}

# ----------------------------------------------------------------
# ALOCAÇÃO E INICIALIZAÇÃO
# ----------------------------------------------------------------

def alloc(+ctx: Sudoku) -> Array<U32>:
  Array.new(U32, 7n, 0)

# Preenche os dígitos 1..9 na fatia da linha
def fill_digits.step(r: Array<U32>, +base: U32, +i: U32) -> Array<U32>:
  Array.set(U32, r, (base + i : U32), (i + 1 : U32))

def fill_digits(k: Nat, arr: Array<U32>, +base: U32, +i: U32) -> Array<U32>:
  match k:
    case 0n:
      arr
    case 1n+p:
      fill_digits(p, fill_digits.step(arr, base, i), base, (i + 1 : U32))

# Embaralha a linha com Fisher-Yates shuffle
def shuffle_row.step(arr: Array<U32>, +base: U32, +i: U32, +seed: U32) -> Array<U32>:
  +j = R.range(seed, (i + 1 : U32))
  Arr.swap_at(~U32, arr, (base + i : U32), (base + j : U32))

def shuffle_row(k: Nat, arr: Array<U32>, +base: U32, +i: U32, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      arr
    case 1n+p:
      shuffle_row(p, shuffle_row.step(arr, base, i, seed), base, (i - 1 : U32), R.step(seed))

def init_row(arr: Array<U32>, +r: U32, +seed: U32) -> Array<U32>:
  +base = (r * 9 : U32)
  filled = fill_digits(9n, arr, base, 0)
  shuffle_row(8n, filled, base, 8, seed)

def init_all(k: Nat, arr: Array<U32>, +r: U32, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      arr
    case 1n+p:
      init_all(p, init_row(arr, r, seed), (r + 1 : U32), R.split.snd(seed))

def init(+ctx: Sudoku, g: Array<U32>, +seed: U32) -> Array<U32>:
  init_all(9n, g, 0, seed)

# ----------------------------------------------------------------
# CRUZAMENTO (OX1 por linha, "4 entram, 4 saem")
# ----------------------------------------------------------------

def key_d(+x: U32) -> U32:
  x

def breed_rows.go(k: Nat,
                  st: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>),
                  +r: U32, +cruza: Bool, +seed: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  match k:
    case 0n:
      st
    case 1n+p:
      (filhos, pais) = st
      (ca, cb) = filhos
      (pa, pb) = pais
      +base = (r * 9 : U32)
      +row_cross = Bool.and(cruza, R.bool(seed))
      next_st = Op.breed_ox1_slice(~U32, ~key_d, ca, cb, pa, pb, base, 9, row_cross, R.split.fst(seed))
      breed_rows.go(p, next_st, (r + 1 : U32), cruza, R.split.snd(seed))

def breed(+ctx: Sudoku, ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, pb: Array<U32>,
          cruza: Bool, +seed: U32) -> (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  breed_rows.go(9n, ((ca, cb), (pa, pb)), 0, cruza, seed)

# ----------------------------------------------------------------
# MUTAÇÃO (Trocas dentro da mesma linha)
# ----------------------------------------------------------------

def mut_one(g: Array<U32>, +seed: U32) -> Array<U32>:
  +r = R.range(seed, 9)
  +s1 = R.step(seed)
  +c1 = R.range(s1, 9)
  +c2 = R.range_except(R.step(s1), 9, c1)
  +base = (r * 9 : U32)
  Arr.swap_at(~U32, g, (base + c1 : U32), (base + c2 : U32))

def mut_swaps(k: Nat, g: Array<U32>, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      g
    case 1n+p:
      mut_swaps(p, mut_one(g, seed), R.split.snd(seed))

def mutate(+ctx: Sudoku, g: Array<U32>, +rate: U32, +seed: U32) -> Array<U32>:
  +count = U32.inc(R.range(seed, 2))
  mut_swaps(U32.to_nat(count), g, R.step(seed))

# ----------------------------------------------------------------
# APTIDÃO (Fitness)
# ----------------------------------------------------------------

type ColState is Type:
  ColState { arr: Array<U32>, +r: U32, +mask: U32 }

def col_mask.val(+c: U32, +r: U32, +mask: U32, res: Array<U32> & U32) -> ColState:
  (arr, +val) = res
  +next_mask = U32.or(mask, U32.shln(1, U32.to_nat(val)))
  ColState{arr, (r + 1 : U32), next_mask}

def col_mask.step(+c: U32, st: ColState) -> ColState:
  match st:
    case ColState{arr, +r, +mask}:
      +idx = ((r * 9 : U32) + c : U32)
      col_mask.val(c, r, mask, Array.get(U32, arr, idx))

def col_mask.go(fuel: Nat, +c: U32, st: ColState) -> ColState:
  match fuel:
    case 0n:
      st
    case 1n+p:
      col_mask.go(p, c, col_mask.step(c, st))

type SumState is Type:
  SumState { arr: Array<U32>, +idx: U32, +acc: U32 }

def sum_cols.from_col(+c: U32, +acc: U32, st: ColState) -> SumState:
  match st:
    case ColState{arr, _, +mask}:
      +pts = Math.bit_count(mask)
      SumState{arr, (c + 1 : U32), (acc + pts : U32)}

def sum_cols.step(st: SumState) -> SumState:
  match st:
    case SumState{arr, +c, +acc}:
      sum_cols.from_col(c, acc, col_mask.go(9n, c, ColState{arr, 0, 0}))

def sum_cols.go(fuel: Nat, st: SumState) -> SumState:
  match fuel:
    case 0n:
      st
    case 1n+p:
      sum_cols.go(p, sum_cols.step(st))

type BoxState is Type:
  BoxState { arr: Array<U32>, +i: U32, +mask: U32 }

def box_mask.val(+i: U32, +mask: U32, res: Array<U32> & U32) -> BoxState:
  (arr, +val) = res
  +next_mask = U32.or(mask, U32.shln(1, U32.to_nat(val)))
  BoxState{arr, (i + 1 : U32), next_mask}

def box_mask.step(+r0: U32, +c0: U32, st: BoxState) -> BoxState:
  match st:
    case BoxState{arr, +i, +mask}:
      +dr = U32.div(i, 3)
      +dc = U32.mod(i, 3)
      +idx = (((r0 + dr : U32) * 9 : U32) + (c0 + dc : U32) : U32)
      box_mask.val(i, mask, Array.get(U32, arr, idx))

def box_mask.go(fuel: Nat, +r0: U32, +c0: U32, st: BoxState) -> BoxState:
  match fuel:
    case 0n:
      st
    case 1n+p:
      box_mask.go(p, r0, c0, box_mask.step(r0, c0, st))

def sum_boxes.from_box(+b: U32, +acc: U32, st: BoxState) -> SumState:
  match st:
    case BoxState{arr, _, +mask}:
      +pts = Math.bit_count(mask)
      SumState{arr, (b + 1 : U32), (acc + pts : U32)}

def sum_boxes.step(st: SumState) -> SumState:
  match st:
    case SumState{arr, +b, +acc}:
      +r0 = (U32.div(b, 3) * 3 : U32)
      +c0 = (U32.mod(b, 3) * 3 : U32)
      sum_boxes.from_box(b, acc, box_mask.go(9n, r0, c0, BoxState{arr, 0, 0}))

def sum_boxes.go(fuel: Nat, st: SumState) -> SumState:
  match fuel:
    case 0n:
      st
    case 1n+p:
      sum_boxes.go(p, sum_boxes.step(st))

def fitness.unpack(st: SumState) -> Array<U32> & U32:
  match st:
    case SumState{arr, _, +score}:
      (arr, (81 + score : U32))

def fitness.boxes(st: SumState) -> Array<U32> & U32:
  match st:
    case SumState{arr, _, +pts_cols}:
      fitness.unpack(sum_boxes.go(9n, SumState{arr, 0, pts_cols}))

def fitness(+ctx: Sudoku, g: Array<U32>) -> Array<U32> & U32:
  fitness.boxes(sum_cols.go(9n, SumState{g, 0, 0}))

# ----------------------------------------------------------------
# HASH (Diversity Check)
# ----------------------------------------------------------------

type HashState is Type:
  HashState { arr: Array<U32>, +i: U32, +acc: U32 }

def hash.val(+i: U32, +acc: U32, res: Array<U32> & U32) -> HashState:
  (arr, +val) = res
  HashState{arr, (i + 1 : U32), (U32.mul(acc, 31) + val : U32)}

def hash.step(st: HashState) -> HashState:
  match st:
    case HashState{arr, +i, +acc}:
      hash.val(i, acc, Array.get(U32, arr, i))

def hash.go(fuel: Nat, st: HashState) -> HashState:
  match fuel:
    case 0n:
      st
    case 1n+p:
      hash.go(p, hash.step(st))

def hash.fin(st: HashState) -> Array<U32> & U32:
  match st:
    case HashState{arr, _, +acc}:
      (arr, acc)

def hash(+ctx: Sudoku, g: Array<U32>) -> Array<U32> & U32:
  hash.fin(hash.go(81n, HashState{g, 0, 7}))

# ----------------------------------------------------------------
# EXIBIÇÃO FORMATADA
# ----------------------------------------------------------------

type ShowRowState is Type:
  ShowRowState { arr: Array<U32>, +c: U32, acc: String }

def show_row.val(+c: U32, acc: String, res: Array<U32> & U32) -> ShowRowState:
  (arr, +val) = res
  +div_col = Bool.pick(String, Bool.or(U32.is_eq(c, 2), U32.is_eq(c, 5)), " | ", " ")
  ShowRowState{arr, (c + 1 : U32), acc ++ U32.show(val) ++ div_col}

def show_row.step(+r: U32, st: ShowRowState) -> ShowRowState:
  match st:
    case ShowRowState{arr, +c, acc}:
      +idx = ((r * 9 : U32) + c : U32)
      show_row.val(c, acc, Array.get(U32, arr, idx))

def show_row.go(fuel: Nat, +r: U32, st: ShowRowState) -> ShowRowState:
  match fuel:
    case 0n:
      st
    case 1n+p:
      show_row.go(p, r, show_row.step(r, st))

type ShowGridState is Type:
  ShowGridState { arr: Array<U32>, +r: U32, acc: String }

def show_grid.from_row(+r: U32, acc: String, row_st: ShowRowState) -> ShowGridState:
  match row_st:
    case ShowRowState{arr, _, row_str}:
      +div_row = Bool.pick(String, Bool.or(U32.is_eq(r, 2), U32.is_eq(r, 5)), "\n  ------+-------+------\n", "\n")
      ShowGridState{arr, (r + 1 : U32), acc ++ row_str ++ div_row}

def show_grid.step(st: ShowGridState) -> ShowGridState:
  match st:
    case ShowGridState{arr, +r, acc}:
      show_grid.from_row(r, acc, show_row.go(9n, r, ShowRowState{arr, 0, "  "}))

def show_grid.go(fuel: Nat, st: ShowGridState) -> ShowGridState:
  match fuel:
    case 0n:
      st
    case 1n+p:
      show_grid.go(p, show_grid.step(st))

def show_grid.fin(st: ShowGridState) -> Array<U32> & String:
  match st:
    case ShowGridState{arr, _, acc}:
      (arr, acc)

def show_grid(arr: Array<U32>) -> Array<U32> & String:
  show_grid.fin(show_grid.go(9n, ShowGridState{arr, 0, ""}))


# ----------------------------------------------------------------
# RELATÓRIO E EXECUÇÃO
# ----------------------------------------------------------------

def relato_final.fin(r: Array<U32> & String, +bf: U32, +gens: U32) -> String:
  (a, grid_str) = r
  +resolvido = U32.is_eq(bf, 243)
  "\n=== RESULTADO FINAL ===\n" ++
  "Gerações: " ++ U32.show(gens) ++ " | Aptidão: " ++ U32.show(bf) ++ "/243" ++
  Bool.pick(String, resolvido, "  (RESOLVIDO COM SUCESSO!)\n\n", "  (NÃO RESOLVIDO)\n\n") ++
  grid_str

def relato_final(g: Array<U32>, +bf: U32, +gens: U32) -> String:
  relato_final.fin(show_grid(g), bf, gens)

def run.fin4(r: Array<A.Individual<Array<U32>>> & A.Individual<Array<U32>>, +bf: U32, +gens: U32) -> String:
  (cur, campeao) = r
  match campeao:
    case A.Individual{gene, fit, _}:
      relato_final(gene, bf, gens)

def run.fin3(cur: Array<A.Individual<Array<U32>>>, h1: A.Individual<Array<U32>>, +bf: U32, +gens: U32) -> String:
  run.fin4(Array.swap(A.Individual<Array<U32>>, cur, 0, h1), bf, gens)

def run.fin2(pop_final: A.Pop<Array<U32>>, +bf: U32, +gens: U32) -> String:
  match pop_final:
    case A.Pop{cur, _, h1, _, _, _, _}:
      run.fin3(cur, h1, bf, gens)

def run.fin(run_final: GA.Run<Array<U32>>, +bf: U32, +gens: U32) -> String:
  match run_final:
    case GA.Run{pop_final, _, _, _, _}:
      run.fin2(pop_final, bf, gens)

def run.best(r: (GA.Run<Array<U32>> & Array<U32>) & U32, +gens: U32) -> String:
  (st, +bf) = r
  (run_final, _) = st
  run.fin(run_final, bf, gens)

def run(+pop_d: U32, +gens: U32, +seed: U32, +demes_d: U32, +epoca: U32, +div: U32, +max_stag: U32) -> String:
  +ctx = sudoku_new()
  +n = U32.shln(1, U32.to_nat(pop_d))
  +cfg = GA.cfg_new(R.per(9, 10), R.per(9, 10), R.per(1, 81), 10, U32.is_ne(div, 0), max_stag)
  +num_epocas = U32.max(U32.div(gens, U32.max(epoca, 1)), 1)
  run.best(
    GA.best_st(~Array<U32>,
      GA.archipelago(~Array<U32>, ~Sudoku, ~alloc, ~init, ~breed, ~mutate, ~fitness, ~hash,
        U32.to_nat(num_epocas), U32.to_nat(demes_d),
        GA.start_st(~Array<U32>, ~Sudoku, ~fitness,
          A.pop_new(~Array<U32>, ~Sudoku, ~alloc, ~init, U32.to_nat(pop_d), ctx, seed), ctx, R.step(seed)),
        ctx, cfg, U32.max(epoca, 1), n)),
    gens)

def go(args: List<String>) -> IO(Unit):
  +nums = IOU.numbers(args)
  # Args: log2(pop) gerações semente log2(demes) época diversidade(0/1) max_stag
  # Defaults: pop=256 (pop_d=8), gens=300, seed=12345, demes=1 (demes_d=0), epoca=10, div=1, max_stag=50
  IO.print(run(IOU.num_at(nums, 0n, 8), IOU.num_at(nums, 1n, 300), IOU.num_at(nums, 2n, 12345),
               IOU.num_at(nums, 3n, 0), IOU.num_at(nums, 4n, 10), IOU.num_at(nums, 5n, 1),
               IOU.num_at(nums, 6n, 50)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), go)
