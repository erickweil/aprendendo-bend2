import Base
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOHelper
import ./../../utils/math.bend as Math
import ./../utils/genes.bend as V
import ./../operators.bend as Op
import ./../mutations.bend as M
import ./../ga.bend as GA

# ================================================================
# CENÁRIO 4: SUDOKU (sudoku.bend)
# ================================================================
# Adaptação do `src/lib/genetic/examples/sudoku.ts`.
#
# Genoma.....: 9 linhas; cada linha guarda APENAS os valores das células
#              livres, como uma permutação dos dígitos que faltam nela: toda
#              linha tem 1..9 e as dicas nunca mudam.
#              ATENÇÃO: isso é mais restritivo que o TS, onde a linha inteira é
#              o genoma, as dicas valem um bônus de +8 e o OX1 pode movê-las —
#              e poder alterar as dicas é o que ajuda a sair do mínimo local.
#              Veja o README do motor.
# Aptidão....: dígitos distintos em cada coluna + em cada caixa 3x3.
#              Máximo 81 + 81 = 162 = resolvido.
# Cruzamento.: por linha, como no TS: 50% OX1 entre as linhas dos pais,
#              senão a linha inteira de um dos pais.
# Mutação....: troca aleatória dentro da linha (mantém a permutação).
# Seleção....: torneio de 10 dentro de cada ilha, com migração.
#
# Uso: bend sudoku.bend [SEMENTE] [PUZZLE] [ILHAS] [POP] [ÉPOCAS] [TORNEIO] [1/TAXA] [DIVERSIDADE 0/1] [MAX_STAG]
#      PUZZLE 0 = fácil, 1 = médio, 2 = difícil
# ================================================================

def puzzle(+k: U32) -> String:
  Bool.pick(String, U32.is_zero(k),
    # fácil (o do teste do TS, o clássico da Wikipédia): 30 dicas
    "530070000600195000098000060800060003400803001700020006060000280000419005000080079",
    Bool.pick(String, U32.is_eq(k, 1),
      # médio: 32 dicas
      "000260701680070090190004500820100040004602900050003028009300074040050036703018000",
      # difícil: 23 dicas
      "000000907000420180000705026100904000050000040000507009920108000034059000507000000"))

# ----------------------------------------------------------------
# CONTEXTO: as dicas e, por linha, os dígitos que faltam
# ----------------------------------------------------------------

type Sudoku is Data:
  Sudoku{clues: List<&2, List<&2, U32>>, missing: List<&2, List<&2, U32>>}

def Sudoku.clues(s: Sudoku) -> List<&2, List<&2, U32>>:
  Sudoku{c, _} = s
  c

def Sudoku.missing(s: Sudoku) -> List<&2, List<&2, U32>>:
  Sudoku{_, m} = s
  m

def to_digits(l: List<&2, Char>) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      Con{(Char.to_u32(c) - 48 : U32), to_digits(t)}

def rows_of(k: Nat, +l: List<&2, U32>) -> List<&2, List<&2, U32>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{V.take(U32, l, 9), rows_of(p, V.drop(U32, l, 9))}

def bit(+v: U32) -> U32:
  U32.shln(1, U32.to_nat(v))

def or_bits(l: List<&2, U32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{h, t}:
      or_bits(t, U32.or(acc, bit(h)))

def put_if(h: U32, rest: List<&2, U32>, keep: Bool) -> List<&2, U32>:
  match keep:
    case True{}:
      Con{h, rest}
    case False{}:
      rest

# Dígitos de `d` a 9 cujo bit não está em `mask`
def absent(k: Nat, +d: U32, +mask: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      put_if(d, absent(p, U32.inc(d), mask), U32.is_zero(U32.and(mask, bit(d))))

def missing_rows(rows: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match rows:
    case Nil{}:
      Nil{}
    case Con{r, t}:
      Con{absent(9n, 1, or_bits(r, 0)), missing_rows(t)}

def parse(+s: String) -> Sudoku:
  +rows = rows_of(9n, to_digits(String.to_list(s)))
  Sudoku{rows, missing_rows(rows)}

# ----------------------------------------------------------------
# A GRADE COMPLETA: dicas + valores livres do genoma
# ----------------------------------------------------------------
# Percorre as dicas da linha consumindo um valor livre a cada 0. Se a célula
# ATUAL é livre desce como parâmetro (`here_free`, com a dica em `here`),
# calculado no passo anterior — match não escrutina valor computado.
def fill.go(rest: List<&2, U32>, free: List<&2, U32>, here_free: Bool, +here: U32) -> List<&2, U32>:
  match rest free here_free:
    case Nil{} Nil{} True{}:
      Con{0, Nil{}}
    case Nil{} Nil{} False{}:
      Con{here, Nil{}}
    case Nil{} Con{f, fs} True{}:
      Con{f, Nil{}}
    case Nil{} Con{f, fs} False{}:
      Con{here, Nil{}}
    case Con{+c, cs} Nil{} True{}:
      Con{0, fill.go(cs, Nil{}, U32.is_zero(c), c)}
    case Con{+c, cs} Nil{} False{}:
      Con{here, fill.go(cs, Nil{}, U32.is_zero(c), c)}
    case Con{+c, cs} Con{f, fs} True{}:
      Con{f, fill.go(cs, fs, U32.is_zero(c), c)}
    case Con{+c, cs} Con{f, fs} False{}:
      Con{here, fill.go(cs, Con{f, fs}, U32.is_zero(c), c)}

def fill_row(clue_row: List<&2, U32>, free: List<&2, U32>) -> List<&2, U32>:
  match clue_row:
    case Nil{}:
      Nil{}
    case Con{+c, cs}:
      fill.go(cs, free, U32.is_zero(c), c)

def grid(clues: List<&2, List<&2, U32>>, gene: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match clues gene:
    case Nil{} Nil{}:
      Nil{}
    case Nil{} Con{g, gs}:
      Nil{}
    case Con{c, cs} Nil{}:
      Nil{}
    case Con{c, cs} Con{g, gs}:
      Con{fill_row(c, g), grid(cs, gs)}

# ----------------------------------------------------------------
# APTIDÃO: dígitos distintos por coluna e por caixa
# ----------------------------------------------------------------
# Cada unidade vira uma máscara de 10 bits (bit d = o dígito d aparece); o
# número de dígitos distintos é o popcount. As máscaras das 9 colunas e das
# 3 caixas da faixa atual vão sendo acumuladas linha a linha, numa varredura.

def bits_of(row: List<&2, U32>) -> List<&2, U32>:
  match row:
    case Nil{}:
      Nil{}
    case Con{v, t}:
      Con{bit(v), bits_of(t)}

def zip_or(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case Nil{} Nil{}:
      Nil{}
    case Nil{} Con{y, ys}:
      Con{y, ys}
    case Con{x, xs} Nil{}:
      Con{x, xs}
    case Con{x, xs} Con{y, ys}:
      Con{U32.or(x, y), zip_or(xs, ys)}

# As máscaras das três caixas que esta linha toca
def box3(+row: List<&2, U32>) -> List<&2, U32>:
  [or_bits(V.take(U32, row, 3), 0),
   or_bits(V.take(U32, V.drop(U32, row, 3), 3), 0),
   or_bits(V.drop(U32, row, 6), 0)]

def sum_pop(l: List<&2, U32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{m, t}:
      sum_pop(t, (acc + Math.popcount(U32.shrn(m, 1n)) : U32))

def zeros(k: Nat) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{0, zeros(p)}

# A cada 3 linhas (fim de uma faixa) as 3 caixas são contadas e zeradas
def score.go(rows: List<&2, List<&2, U32>>, +r: U32, cols: List<&2, U32>,
             band: List<&2, U32>, +acc: U32) -> U32:
  match rows:
    case Nil{}:
      (acc + sum_pop(cols, 0) : U32)
    case Con{+row, t}:
      +band2 = zip_or(band, box3(row))
      +flush = U32.is_eq(U32.mod(r, 3), 2)
      score.go(t, U32.inc(r), zip_or(cols, bits_of(row)),
               Bool.pick(List<&2, U32>, flush, zeros(3n), band2),
               (acc + Bool.pick(U32, flush, sum_pop(band2, 0), 0) : U32))

def MAX_FIT() -> U32:
  162

def fitness(ctx: Sudoku, gene: List<&2, List<&2, U32>>) -> U32:
  score.go(grid(Sudoku.clues(ctx), gene), 0, zeros(9n), zeros(3n), 0)

# ----------------------------------------------------------------
# INICIALIZAÇÃO, CRUZAMENTO E MUTAÇÃO
# ----------------------------------------------------------------

def shuffle_rows(rows: List<&2, List<&2, U32>>, +seed: U32) -> List<&2, List<&2, U32>>:
  match rows:
    case Nil{}:
      Nil{}
    case Con{+m, t}:
      Con{V.shuffle(~U32, m, V.len(U32, m), seed), shuffle_rows(t, R.split.trd(seed))}

def init_gene(ctx: Sudoku, seed: U32) -> List<&2, List<&2, U32>>:
  shuffle_rows(Sudoku.missing(ctx), seed)

# A chave do OX1 é o próprio dígito, então há 10 chaves possíveis (0..9)
def key(g: U32) -> U32:
  g

def row_hash(r: List<&2, U32>) -> U32:
  V.hash_list(~U32, ~key, r, 7)

# Hash de Rust/TS: polinomial sobre todas as células livres
def hash(ctx: Sudoku, g: List<&2, List<&2, U32>>) -> U32:
  V.hash_list(~List<&2, U32>, ~row_hash, g, 7)

def row_pick(do_ox: Bool, take_a: Bool, ra: List<&2, U32>, rb: List<&2, U32>,
             +n: U32, +seed: U32) -> List<&2, U32>:
  match do_ox take_a:
    case True{} True{}:
      Op.cross_ox1(~U32, ~key, ra, rb, n, 10, seed)
    case True{} False{}:
      Op.cross_ox1(~U32, ~key, ra, rb, n, 10, seed)
    case False{} True{}:
      ra
    case False{} False{}:
      rb

def cross.go(a: List<&2, List<&2, U32>>, b: List<&2, List<&2, U32>>, +seed: U32) -> List<&2, List<&2, U32>>:
  match a b:
    case Nil{} Nil{}:
      Nil{}
    case Nil{} Con{y, ys}:
      Nil{}
    case Con{x, xs} Nil{}:
      Nil{}
    case Con{+x, xs} Con{y, ys}:
      +n = V.len(U32, x)
      +s1 = R.step(seed)
      # OX1 só faz sentido com 2+ células livres
      Con{row_pick(Bool.and(U32.is_ge(n, 2), R.hit(seed, R.per(1, 2))), R.hit(s1, R.per(1, 2)), x, y, n, R.step(s1)),
          cross.go(xs, ys, R.split.trd(seed))}

def cross(ctx: Sudoku, a: List<&2, List<&2, U32>>, b: List<&2, List<&2, U32>>, seed: U32) -> List<&2, List<&2, U32>>:
  cross.go(a, b, seed)

def mutate.go(rows: List<&2, List<&2, U32>>, +rate: U32, +seed: U32) -> List<&2, List<&2, U32>>:
  match rows:
    case Nil{}:
      Nil{}
    case Con{+r, t}:
      Con{M.mut_swap(~U32, r, V.len(U32, r), rate, seed), mutate.go(t, rate, R.split.trd(seed))}

def mutate(ctx: Sudoku, g: List<&2, List<&2, U32>>, rate: U32, seed: U32) -> List<&2, List<&2, U32>>:
  mutate.go(g, rate, seed)

# ----------------------------------------------------------------
# SAÍDA
# ----------------------------------------------------------------

def show_row.go(row: List<&2, U32>, +c: U32) -> String:
  match row:
    case Nil{}:
      ""
    case Con{+v, t}:
      Bool.pick(String, U32.is_zero(v), ".", U32.show(v)) ++
      Bool.pick(String, Bool.or(U32.is_eq(c, 2), U32.is_eq(c, 5)), " | ", " ") ++
      show_row.go(t, U32.inc(c))

def show_grid.go(rows: List<&2, List<&2, U32>>, +r: U32) -> String:
  match rows:
    case Nil{}:
      ""
    case Con{row, t}:
      "  " ++ show_row.go(row, 0) ++ "\n" ++
      Bool.pick(String, Bool.or(U32.is_eq(r, 2), U32.is_eq(r, 5)), "  ------+-------+------\n", "") ++
      show_grid.go(t, U32.inc(r))

def show_grid(rows: List<&2, List<&2, U32>>) -> String:
  show_grid.go(rows, 0)

# ----------------------------------------------------------------
# EXECUÇÃO
# ----------------------------------------------------------------

def best(arch: GA.ArchTree<List<&2, List<&2, U32>>>) -> GA.Ind<List<&2, List<&2, U32>>>:
  GA.best_archipelago(List<&2, List<&2, U32>>, arch)

def best_fit(arch: GA.ArchTree<List<&2, List<&2, U32>>>) -> U32:
  GA.Ind.fit(List<&2, List<&2, U32>>, best(arch))

def finish(+ctx: Sudoku, arch: GA.ArchTree<List<&2, List<&2, U32>>>, +gens: U32) -> IO(Unit):
  +b = best(arch)
  +f = GA.Ind.fit(List<&2, List<&2, U32>>, b)
  IO.print(
    "\nMelhor grade (aptidão " ++ U32.show(f) ++ " / 162, até a geração " ++ U32.show(gens) ++ "):\n" ++
    show_grid(grid(Sudoku.clues(ctx), GA.Ind.gene(List<&2, List<&2, U32>>, b))) ++
    "Resolvido? " ++ Bool.show(U32.is_eq(f, MAX_FIT())))

def report(k: Nat, arch: GA.ArchTree<List<&2, List<&2, U32>>>, done: Bool, +e: Nat,
           +gens: U32, +ctx: Sudoku, +cfg: GA.Config, +seed: U32) -> IO(Unit):
  match k done:
    case 0n True{}:
      finish(ctx, arch, gens)
    case 0n False{}:
      finish(ctx, arch, gens)
    case 1n+p True{}:
      finish(ctx, arch, gens)
    case 1n+p False{}:
      +next = GA.run_archipelago(~Sudoku, ~List<&2, List<&2, U32>>, ~init_gene, ~fitness, ~hash, ~cross, ~mutate, 1n, arch, e, ctx, cfg, seed)
      +now = (gens + U32.from_nat(e) : U32)
      IO.bind(Unit, Unit,
        IO.print("  geração " ++ U32.show(now) ++ ": " ++ U32.show(best_fit(next)) ++ " / 162"),
        u => report(p, next, GA.arch_done(List<&2, List<&2, U32>>, cfg, next), e, now, ctx, cfg, R.split.trd(seed)))

def run(args: List<String>) -> IO(Unit):
  +nums = IOHelper.numbers(args)
  +s0 = IOHelper.num_at(nums, 0n, 20260918)
  +pz = IOHelper.num_at(nums, 1n, 0)
  +isl = IOHelper.num_at(nums, 2n, 3)
  +pop = IOHelper.num_at(nums, 3n, 6)
  +epochs = IOHelper.num_at(nums, 4n, 100)
  +tsize = IOHelper.num_at(nums, 5n, 10)
  +gene_den = IOHelper.num_at(nums, 6n, 81)
  +div = IOHelper.num_at(nums, 7n, 1)
  +max_stag = IOHelper.num_at(nums, 8n, 500)
  +ctx = parse(puzzle(pz))
  # como no teste do TS: 90% / 90% / 1 por 81 genes, torneio de 10
  +cfg = GA.config(R.per(9, 10), R.per(9, 10), R.per(1, gene_den), tsize, max_stag, MAX_FIT(), pop, div)
  +a0 = GA.gen_archipelago(~Sudoku, ~List<&2, List<&2, U32>>, ~init_gene, ~fitness, U32.to_nat(isl), ctx, cfg, s0)
  IO.bind(Unit, Unit,
    IO.print(
      "=== CENÁRIO 4: SUDOKU (puzzle " ++ U32.show(pz) ++ ") ===\n" ++
      show_grid(Sudoku.clues(ctx)) ++
      "Ilhas: " ++ U32.show(U32.shln(1, U32.to_nat(isl))) ++ " x " ++
      U32.show(U32.shln(1, U32.to_nat(pop))) ++ " indivíduos, épocas de 20 gerações\n" ++
      "  geração 0: " ++ U32.show(best_fit(a0)) ++ " / 162"),
    u => report(U32.to_nat(epochs), a0, GA.arch_done(List<&2, List<&2, U32>>, cfg, a0), 20n, 0, ctx, cfg, R.step(s0)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
