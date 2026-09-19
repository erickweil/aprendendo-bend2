import Base
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOHelper
import ./../../utils/math.bend as Math
import ./../utils/genes.bend as V
import ./../operators.bend as Op
import ./../ga.bend as GA

# ================================================================
# CENÁRIO 4: SUDOKU (sudoku.bend)
# ================================================================
# Porte do `src/lib/genetic/examples/sudoku.ts`, no mesmo modelo.
#
# Genoma.....: as 81 células, como o `quadro` do TS, guardadas como 9 linhas
#              de 9 (o TS tem `rows`, views sobre o mesmo quadro). Cada linha
#              começa como uma permutação de 1..9 com as dicas no lugar.
# Aptidão....: para cada linha, coluna e caixa, quantos dígitos aparecem
#              EXATAMENTE uma vez (máximo 243), mais +8 por dica mantida.
# Cruzamento.: por linha, 50% OX1 entre as linhas dos pais, senão a linha
#              inteira de um dos pais. O OX1 PODE MOVER AS DICAS: elas são
#              mantidas só pelo bônus da aptidão. Isso é essencial — é o
#              caminho por estados "inválidos" que tira a busca do mínimo
#              local (uma versão anterior travava as dicas e empacava).
# Mutação....: troca de duas células livres da mesma linha (a mutação não
#              mexe nas dicas, como no TS). A QUANTIDADE de trocas é uma
#              amostra de Poisson com média 81 x taxa: com a taxa 1/81, uma
#              troca por quadro em média.
# Seleção....: torneio de 10 dentro de cada ilha, diversity_check, migração
#              em anel. Configuração do teste do TS: 90% / 90% / 1/81.
#
# Uso: bend sudoku.bend [SEMENTE] [PUZZLE] [ILHAS] [POP] [ÉPOCAS] [TORNEIO]
#                       [1/TAXA] [DIVERSIDADE 0/1] [MAX_STAG]
#      PUZZLE 0 = fácil, 1 = médio, 2 = difícil, 3 = quadro vazio
# ================================================================

def puzzle(+k: U32) -> String:
  Bool.pick(String, U32.is_zero(k),
    # fácil (o do teste do TS, o clássico da Wikipédia): 30 dicas
    "530070000600195000098000060800060003400803001700020006060000280000419005000080079",
    Bool.pick(String, U32.is_eq(k, 1),
      # médio: 32 dicas
      "000260701680070090190004500820100040004602900050003028009300074040050036703018000",
      Bool.pick(String, U32.is_eq(k, 2),
        # difícil: 23 dicas
        "000000907000420180000705026100904000050000040000507009920108000034059000507000000",
        # vazio: qualquer quadro válido serve
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000")))

# ----------------------------------------------------------------
# CONTEXTO
# ----------------------------------------------------------------
#   clues  : as 9 linhas de dicas (0 = livre)
#   free   : índices (0..80) das células livres
#   nfree  : quantas são
#   nclues : quantas dicas

type Sudoku is Data:
  Sudoku{clues: List<&2, List<&2, U32>>, free: List<&2, U32>, nfree: U32, nclues: U32}

def Sudoku.clues(s: Sudoku) -> List<&2, List<&2, U32>>:
  Sudoku{c, _, _, _} = s
  c

def Sudoku.free(s: Sudoku) -> List<&2, U32>:
  Sudoku{_, f, _, _} = s
  f

def Sudoku.nfree(s: Sudoku) -> U32:
  Sudoku{_, _, n, _} = s
  n

def Sudoku.nclues(s: Sudoku) -> U32:
  Sudoku{_, _, _, n} = s
  n

def to_digits(l: List<&2, Char>) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      Con{(Char.to_u32(c) - 48 : U32), to_digits(t)}

def put_if(h: U32, rest: List<&2, U32>, keep: Bool) -> List<&2, U32>:
  match keep:
    case True{}:
      Con{h, rest}
    case False{}:
      rest

# Índices das células livres, a partir da posição `i`
def free_of(l: List<&2, U32>, +i: U32) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      put_if(i, free_of(t, U32.inc(i)), U32.is_zero(c))

# ----------------------------------------------------------------
# LINHAS
# ----------------------------------------------------------------

def rows_of(k: Nat, +l: List<&2, U32>) -> List<&2, List<&2, U32>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{V.take(U32, l, 9), rows_of(p, V.drop(U32, l, 9))}

def parse(+s: String) -> Sudoku:
  +flat = to_digits(String.to_list(s))
  +free = free_of(flat, 0)
  +nfree = V.len(U32, free)
  Sudoku{rows_of(9n, flat), free, nfree, (81 - nfree : U32)}

def bit(+v: U32) -> U32:
  U32.shln(1, U32.to_nat(v))

def or_bits(l: List<&2, U32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{h, t}:
      or_bits(t, U32.or(acc, bit(h)))

# Dígitos de `d` a 9 cujo bit não está em `mask`
def absent(k: Nat, +d: U32, +mask: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      put_if(d, absent(p, U32.inc(d), mask), U32.is_zero(U32.and(mask, bit(d))))

# Põe os valores de `free` nas posições 0 da linha de dicas, na ordem.
# Se a célula ATUAL é livre desce como parâmetro (`here_free`, com a dica em
# `here`), calculado no passo anterior — match não escrutina valor computado.
def fill.go(rest: List<&2, U32>, free: List<&2, U32>, here_free: Bool, +here: U32) -> List<&2, U32>:
  match rest free here_free:
    case Nil{} Con{f, fs} True{}:
      Con{f, Nil{}}
    case Nil{} _ _:
      Con{here, Nil{}}
    case Con{+c, cs} Con{f, fs} True{}:
      Con{f, fill.go(cs, fs, U32.is_zero(c), c)}
    case Con{+c, cs} _ _:
      Con{here, fill.go(cs, free, U32.is_zero(c), c)}

def fill_row(clue_row: List<&2, U32>, free: List<&2, U32>) -> List<&2, U32>:
  match clue_row:
    case Nil{}:
      Nil{}
    case Con{+c, cs}:
      fill.go(cs, free, U32.is_zero(c), c)

# ----------------------------------------------------------------
# INICIALIZAÇÃO (fillRandom do TS)
# ----------------------------------------------------------------
# Cada linha: as dicas no lugar e os dígitos que faltam embaralhados nas
# células livres. Toda linha começa como uma permutação de 1..9.

def random_rows(rows: List<&2, List<&2, U32>>, +seed: U32) -> List<&2, List<&2, U32>>:
  match rows:
    case Nil{}:
      Nil{}
    case Con{+r, t}:
      +miss = absent(9n, 1, or_bits(r, 0))
      Con{fill_row(r, V.shuffle(~U32, miss, V.len(U32, miss), seed)), random_rows(t, R.split.trd(seed))}

def init_gene(ctx: Sudoku, seed: U32) -> List<&2, List<&2, U32>>:
  random_rows(Sudoku.clues(ctx), seed)

# ----------------------------------------------------------------
# APTIDÃO (fitness do TS)
# ----------------------------------------------------------------
# Para cada unidade (linha, coluna, caixa), quantos dígitos aparecem
# EXATAMENTE uma vez. Cada unidade guarda duas máscaras de bits num U32:
# `s1` (dígitos vistos, 16 bits baixos) e `s2` (vistos duas vezes ou mais,
# 16 bits altos); os que aparecem uma vez só são `s1 & ~s2`.
#
# As 27 unidades ficam num `Array` local (linhas em 0..8, colunas em 9..17,
# caixas em 18..26) e o quadro é percorrido UMA vez: cada célula atualiza
# suas três unidades em O(1). (Uma primeira versão acumulava colunas e caixas
# em listas, linha a linha, e custava 5x mais.)

def once(+s1: U32, +s2: U32) -> U32:
  Math.popcount(U32.shrn(U32.and(s1, U32.not(s2)), 1n))

def unit_add(+u: U32, +b: U32) -> U32:
  +s1 = U32.and(u, 65535)
  U32.or(U32.or(s1, b), U32.or(U32.and(u, 4294901760), U32.shln(U32.and(s1, b), 16n)))

def unit_once(+u: U32) -> U32:
  once(U32.and(u, 65535), U32.shrn(u, 16n))

# Atualiza a unidade `k`. Recebe o par que `Array.swap` devolve (desestruturar
# um PARÂMETRO é permitido; o retorno de uma chamada, não).
def upd_slot(r: Array<U32> & U32, +k: U32, +b: U32) -> Array<U32>:
  (a, old) = r
  Array.set(U32, a, k, unit_add(old, b))

def upd(a: Array<U32>, +k: U32, +b: U32) -> Array<U32>:
  upd_slot(Array.swap(U32, a, k, 0), k, b)

def cells(row: List<&2, U32>, a: Array<U32>, +r: U32, +c: U32) -> Array<U32>:
  match row:
    case Nil{}:
      a
    case Con{v, t}:
      +b = bit(v)
      +box = (18 + (U32.div(r, 3) * 3 : U32) + U32.div(c, 3) : U32)
      a1 = upd(a, r, b)
      a2 = upd(a1, (9 + c : U32), b)
      cells(t, upd(a2, box, b), r, U32.inc(c))

def rows_cells(rows: List<&2, List<&2, U32>>, a: Array<U32>, +r: U32) -> Array<U32>:
  match rows:
    case Nil{}:
      a
    case Con{row, t}:
      rows_cells(t, cells(row, a, r, 0), U32.inc(r))

# Soma as 27 unidades; o par (array, unidade lida) é o estado do laço
def sum_units(k: Nat, r: Array<U32> & U32, +i: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      (a, u) = r
      (acc + unit_once(u) : U32)
    case 1n+p:
      (a, u) = r
      +j = U32.inc(i)
      sum_units(p, Array.get(U32, a, j), j, (acc + unit_once(u) : U32))

# +8 por dica mantida no lugar
def row_bonus(g: List<&2, U32>, clues: List<&2, U32>, +acc: U32) -> U32:
  match g clues:
    case Con{+v, vt} Con{+c, ct}:
      row_bonus(vt, ct, (acc + Bool.pick(U32, Bool.and(Bool.not(U32.is_zero(c)), U32.is_eq(v, c)), 8, 0) : U32))
    case _ _:
      acc

def clue_bonus(g: List<&2, List<&2, U32>>, clues: List<&2, List<&2, U32>>, +acc: U32) -> U32:
  match g clues:
    case Con{r, rt} Con{c, ct}:
      clue_bonus(rt, ct, row_bonus(r, c, acc))
    case _ _:
      acc

def max_fitness(+ctx: Sudoku) -> U32:
  (243 + (8 * Sudoku.nclues(ctx) : U32) : U32)

def fitness(ctx: Sudoku, gene: List<&2, List<&2, U32>>) -> U32:
  +gene = gene
  sum_units(26n, Array.get(U32, rows_cells(gene, Array.new(U32, 5n, 0), 0), 0), 0,
            clue_bonus(gene, Sudoku.clues(ctx), 0))

# ----------------------------------------------------------------
# CRUZAMENTO (por linha, como no TS)
# ----------------------------------------------------------------

# Chave do OX1: o próprio dígito (10 chaves possíveis, 0..9)
def key(g: U32) -> U32:
  g

def row_pick(do_ox: Bool, take_a: Bool, ra: List<&2, U32>, rb: List<&2, U32>, +seed: U32) -> List<&2, U32>:
  match do_ox take_a:
    case True{} _:
      Op.cross_ox1(~U32, ~key, ra, rb, 9, 10, seed)
    case False{} True{}:
      ra
    case False{} False{}:
      rb

def cross.go(a: List<&2, List<&2, U32>>, b: List<&2, List<&2, U32>>, +seed: U32) -> List<&2, List<&2, U32>>:
  match a b:
    case Con{x, xs} Con{y, ys}:
      +s1 = R.step(seed)
      Con{row_pick(R.bool(seed), R.bool(s1), x, y, R.step(s1)), cross.go(xs, ys, R.split.trd(seed))}
    case _ _:
      Nil{}

def cross(ctx: Sudoku, a: List<&2, List<&2, U32>>, b: List<&2, List<&2, U32>>, seed: U32) -> List<&2, List<&2, U32>>:
  cross.go(a, b, seed)

# ----------------------------------------------------------------
# MUTAÇÃO (mutate do TS, com a quantidade de Poisson)
# ----------------------------------------------------------------
# A primeira célula é sorteada entre as livres; a segunda entre as livres da
# MESMA linha, diferente da primeira.

# Células livres da linha `row`, na ordem
def free_in_row(l: List<&2, U32>, +row: U32) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+i, t}:
      put_if(i, free_in_row(t, row), U32.is_eq(U32.div(i, 9), row))

# Posição de `x` na lista (ou o comprimento, se não estiver)
def index_of.go(l: List<&2, U32>, found: Bool, +x: U32, +i: U32) -> U32:
  match l found:
    case _ True{}:
      i
    case Nil{} False{}:
      U32.inc(i)
    case Con{h, t} False{}:
      index_of.go(t, U32.is_eq(h, x), x, U32.inc(i))

def index_of(l: List<&2, U32>, +x: U32) -> U32:
  match l:
    case Nil{}:
      0
    case Con{h, t}:
      index_of.go(t, U32.is_eq(h, x), x, 0)

# Troca, na linha `r`, as colunas `c1` e `c2` (só essa linha é reconstruída)
def swap_cells(+rows: List<&2, List<&2, U32>>, +r: U32, +c1: U32, +c2: U32) -> List<&2, List<&2, U32>>:
  V.set_at(List<&2, U32>, rows, r, V.swap_at(U32, V.nth(List<&2, U32>, rows, r, Nil{}), c1, c2, 0))

def swap_in_row(+rows: List<&2, List<&2, U32>>, +ctx: Sudoku, +seed: U32) -> List<&2, List<&2, U32>>:
  +i = V.nth(U32, Sudoku.free(ctx), R.range(seed, Sudoku.nfree(ctx)), 0)
  +row = free_in_row(Sudoku.free(ctx), U32.div(i, 9))
  # com uma só célula livre na linha não há troca: j = i
  +j = V.nth(U32, row, R.range_except(R.step(seed), V.len(U32, row), index_of(row, i)), i)
  swap_cells(rows, U32.div(i, 9), U32.mod(i, 9), U32.mod(j, 9))

def swaps(k: Nat, +rows: List<&2, List<&2, U32>>, +ctx: Sudoku, +seed: U32) -> List<&2, List<&2, U32>>:
  match k:
    case 0n:
      rows
    case 1n+p:
      swaps(p, swap_in_row(rows, ctx, seed), ctx, R.split.trd(seed))

def mutate(ctx: Sudoku, g: List<&2, List<&2, U32>>, rate: U32, seed: U32) -> List<&2, List<&2, U32>>:
  +seed = seed
  +k = R.poisson(seed, (U32.to_f32(81) * R.prob(rate) : F32))
  swaps(U32.to_nat(k), g, ctx, R.step(seed))

# Hash polinomial do quadro (o hash do TS)
def row_hash(r: List<&2, U32>) -> U32:
  V.hash_list(~U32, ~key, r, 7)

def hash(ctx: Sudoku, g: List<&2, List<&2, U32>>) -> U32:
  V.hash_list(~List<&2, U32>, ~row_hash, g, 7)

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

def show_grid(g: List<&2, List<&2, U32>>) -> String:
  show_grid.go(g, 0)

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
  +maxf = max_fitness(ctx)
  IO.print(
    "\nMelhor quadro (aptidão " ++ U32.show(f) ++ " / " ++ U32.show(maxf) ++
    ", até a geração " ++ U32.show(gens) ++ "):\n" ++
    show_grid(GA.Ind.gene(List<&2, List<&2, U32>>, b)) ++
    "Resolvido? " ++ Bool.show(U32.is_eq(f, maxf)))

def report(k: Nat, arch: GA.ArchTree<List<&2, List<&2, U32>>>, done: Bool, +e: Nat,
           +gens: U32, +ctx: Sudoku, +cfg: GA.Config, +seed: U32) -> IO(Unit):
  match k done:
    case _ True{}:
      finish(ctx, arch, gens)
    case 0n False{}:
      finish(ctx, arch, gens)
    case 1n+p False{}:
      +next = GA.run_archipelago(~Sudoku, ~List<&2, List<&2, U32>>, ~init_gene, ~fitness, ~hash, ~cross, ~mutate, 1n, arch, e, ctx, cfg, seed)
      +now = (gens + U32.from_nat(e) : U32)
      IO.bind(Unit, Unit,
        IO.print("  geração " ++ U32.show(now) ++ ": " ++ U32.show(best_fit(next)) ++ " / " ++ U32.show(max_fitness(ctx))),
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
  +max_stag = IOHelper.num_at(nums, 8n, 10000)
  +ctx = parse(puzzle(pz))
  +cfg = GA.config(R.per(9, 10), R.per(9, 10), R.per(1, gene_den), tsize, max_stag, max_fitness(ctx), pop, div)
  +a0 = GA.gen_archipelago(~Sudoku, ~List<&2, List<&2, U32>>, ~init_gene, ~fitness, U32.to_nat(isl), ctx, cfg, s0)
  IO.bind(Unit, Unit,
    IO.print(
      "=== CENÁRIO 4: SUDOKU (puzzle " ++ U32.show(pz) ++ ", " ++ U32.show(Sudoku.nclues(ctx)) ++ " dicas) ===\n" ++
      show_grid(Sudoku.clues(ctx)) ++
      "Ilhas: " ++ U32.show(U32.shln(1, U32.to_nat(isl))) ++ " x " ++
      U32.show(U32.shln(1, U32.to_nat(pop))) ++ " indivíduos, épocas de 20 gerações\n" ++
      "  geração 0: " ++ U32.show(best_fit(a0)) ++ " / " ++ U32.show(max_fitness(ctx))),
    u => report(U32.to_nat(epochs), a0, GA.arch_done(List<&2, List<&2, U32>>, cfg, a0), 20n, 0, ctx, cfg, R.step(s0)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
