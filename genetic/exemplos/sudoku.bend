import Base
import ./../arena.bend as A
import ./../operators.bend as Op
import ./../ga.bend as GA
import ./../../utils/arrays.bend as Arr
import ./../../utils/random.bend as R
import ./../../utils/math.bend as Math
import ./../../utils/io.bend as IOU

# ================================================================
# SUDOKU — quadro vazio OU com dicas
# ================================================================
# Codificação "row-permutation", a mesma do motor em TS
# (my-website, src/lib/genetic/examples/sudoku.ts): cada LINHA é sempre uma
# permutação de 1..9, então linha nunca repete dígito e a busca é por colunas
# e caixas. O cruzamento (OX1 por linha) e a mutação (troca dentro da linha)
# preservam essa invariante.
#
# As DICAS são móveis: ficam no genoma como qualquer outro gene e são
# sustentadas por um BÔNUS de aptidão (+8 por dica no lugar), não travadas por
# construção. Travar as dicas na representação (genoma = só as células livres)
# foi tentado antes e é um passo atrás — prende a busca num ótimo local.
#
# ---------------- layout do genoma (Array<U32>, 2^8 = 256) ----------------
#     0.. 80   tabuleiro, célula (r,c) no índice r*9+c
#    81..161   dicas (constante; escrita pelo init, nunca pelo cruzamento)
#   162..171   marcas do OX1 (uma por dígito 0..9)
#   172..180   rascunho: colunas livres da linha em construção
#   181..255   folga
#
# Carregar as dicas DENTRO do genoma é o que mantém o caminho quente livre do
# contexto: `fitness` e `mutate` precisam de acesso aleatório a `dica[i]`, e o
# contexto é `Data` (não pode guardar Array), então lê-lo seria travessia de
# lista mais um atômico por leitura. Aqui é um `Array.get` de 0,55 ns. Custa 81
# palavras por indivíduo, e o contexto só é tocado no `init`, que é frio.
#
# ⚠️ A aptidão nunca é 0 (vale no mínimo 81, das linhas), então não colide com
# a marca de "não avaliado" da arena.
# ================================================================

def LADO() -> U32:
  9

def CELULAS() -> U32:
  81

def OFF_DICAS() -> U32:
  81

def OFF_MARCAS() -> U32:
  162

def OFF_LIVRES() -> U32:
  172

# ----------------------------------------------------------------
# CONTEXTO (Data, frio: só o init o lê)
# ----------------------------------------------------------------

# ⚠️ O contexto guarda SÓ ESCALARES, e isso é uma decisão de desempenho, não
# de estilo. O motor duplica o contexto (`+ctx`) em toda chamada de callback,
# em todas as tarefas. Se ele contiver qualquer estrutura de heap — uma
# `List` com as 81 dicas, por exemplo — cada duplicação mexe num contador de
# referências COMPARTILHADO entre as tarefas, e isso é um atômico contestado
# no caminho quente (AGENTS.md, Armadilha 3).
#
# Medido, 8 demes em 8 E-cores homogêneos, quadro vazio, 5000 gerações:
#   contexto com a `List` das dicas : 6,61 s -> 4,18 s   (1,58x)
#   contexto só com escalares       : 5,61 s -> 0,95 s   (5,91x)
# O paralelismo quase quadruplicou, e o caso de um núcleo ainda ficou mais
# rápido. Por isso o contexto carrega apenas QUAL quadro é, e o `init` (que é
# frio) reconstrói a lista de dicas localmente a cada chamada.
type Sudoku is Data:
  Sudoku{qual: U32, n_dicas: U32}

def sud_qual(+s: Sudoku) -> U32:
  match s:
    case Sudoku{+qual, n_dicas}:
      qual

def sud_n(+s: Sudoku) -> U32:
  match s:
    case Sudoku{qual, +n_dicas}:
      n_dicas

def quadro(+k: U32) -> String:
  Bool.pick(String, U32.is_zero(k),
    "000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    Bool.pick(String, U32.is_eq(k, 1),
      "530070000600195000098000060800060003400803001700020006060000280000419005000080079",
      Bool.pick(String, U32.is_eq(k, 2),
        "000260701680070090190004500820100040004602900050003028009300074040050036703018000",
        "000000907000420180000705026100904000050000040000507009920108000034059000507000000")))

def to_digits(l: List<&2, Char>) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      Con{(Char.to_u32(c) - 48 : U32), to_digits(t)}

def conta_dicas(l: List<&2, U32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{+h, t}:
      conta_dicas(t, (acc + Bool.to_u32(U32.is_ne(h, 0)) : U32))

def dicas_de(+k: U32) -> List<&2, U32>:
  to_digits(String.to_list(quadro(k)))

def sudoku_new(+k: U32) -> Sudoku:
  Sudoku{k, conta_dicas(dicas_de(k), 0)}

# ----------------------------------------------------------------
# PERCURSOS (é o que o `fold_idx` precisa saber sobre um sudoku)
# ----------------------------------------------------------------
# Três funções de uma linha cada, no lugar de três andaimes de laço.

def idx_linha(+r: U32, +k: U32) -> U32:
  ((r * 9 : U32) + k : U32)

def idx_coluna(+c: U32, +k: U32) -> U32:
  ((k * 9 : U32) + c : U32)

def idx_caixa(+b: U32, +k: U32) -> U32:
  ((((U32.div(b, 3) * 3 : U32) + U32.div(k, 3) : U32) * 9 : U32) +
   ((U32.mod(b, 3) * 3 : U32) + U32.mod(k, 3) : U32) : U32)

# ----------------------------------------------------------------
# APTIDÃO
# ----------------------------------------------------------------
# Critério do TS: por unidade (linha, coluna, caixa), quantos dígitos aparecem
# EXATAMENTE uma vez. Cada unidade cabe num U32: os 16 bits baixos são
# "dígito visto" e os 16 altos "visto duas vezes ou mais"; quem aparece uma só
# vez é `s1 & ~s2`. Nenhum contador, nenhuma alocação.

def bit_de(+v: U32) -> U32:
  U32.shln(1, U32.to_nat(v))

# `acc` chega linear (a assinatura do template manda), então é religado com
# `+u = acc` para poder ser lido mais de uma vez
def unidade_add(+x: U32, acc: U32, +k: U32) -> U32:
  +u = acc
  +s1 = U32.and(u, 65535)
  +b = bit_de(x)
  U32.or(U32.or(s1, b), U32.or(U32.and(u, 4294901760), U32.shln(U32.and(s1, b), 16n)))

# `>> 1` descarta o bit do dígito 0 (célula vazia não vale ponto)
def unidade_uma_vez(+u: U32) -> U32:
  Math.bit_count(U32.shrn(U32.and(U32.and(u, 65535), U32.not(U32.shrn(u, 16n))), 1n))

# --- somar as 9 unidades de uma família ---
# UM laço, parametrizado pelo percurso: serve para linhas, colunas e caixas.

def unidades.add(+acc: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (a, +u) = r
  (a, (acc + unidade_uma_vez(u) : U32))

def unidades.go(~idx_of: @+c: U32 -> @+k: U32 -> U32, k: Nat, st: Array<U32> & U32,
                +c: U32) -> Array<U32> & U32:
  match k:
    case 0n:
      st
    case 1n+p:
      (a, +acc) = st
      unidades.go(~idx_of, p,
        unidades.add(acc, Arr.fold_idx(~U32, ~U32, ~idx_of, ~unidade_add, a, 0, c, 9)),
        (c + 1 : U32))

def unidades(~idx_of: @+c: U32 -> @+k: U32 -> U32, st: Array<U32> & U32) -> Array<U32> & U32:
  unidades.go(~idx_of, 9n, st, 0)

# --- bônus das dicas: +8 por dica que continua no lugar ---
# Lê DUAS posições por célula (tabuleiro e dica), então não é um `fold_idx`.

def bonus.cmp(+dica: U32, +acc: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (a, +v) = r
  (a, (acc + Bool.pick(U32, Bool.and(U32.is_ne(dica, 0), U32.is_eq(v, dica)), 8, 0) : U32))

def bonus.rd(+acc: U32, +i: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (a, +dica) = r
  bonus.cmp(dica, acc, Array.get(U32, a, i))

def bonus.go(k: Nat, st: Array<U32> & U32, +i: U32) -> Array<U32> & U32:
  match k:
    case 0n:
      st
    case 1n+p:
      (a, +acc) = st
      bonus.go(p, bonus.rd(acc, i, Array.get(U32, a, (OFF_DICAS() + i : U32))), (i + 1 : U32))

def fitness(+ctx: Sudoku, g: Array<U32>) -> Array<U32> & U32:
  bonus.go(81n, unidades(~idx_caixa, unidades(~idx_coluna, unidades(~idx_linha, (g, 0)))), 0)

def max_fitness(+ctx: Sudoku) -> U32:
  (243 + (8 * sud_n(ctx) : U32) : U32)

# ----------------------------------------------------------------
# INICIALIZAÇÃO
# ----------------------------------------------------------------
# Por linha: as dicas ficam onde estão; os dígitos que faltam entram nas
# células livres e são embaralhados entre si (Fisher-Yates restrito às
# livres). A invariante "cada linha é permutação de 1..9" nasce aqui.

def grava_dicas(l: List<&2, U32>, a: Array<U32>, +i: U32) -> Array<U32>:
  match l:
    case Nil{}:
      a
    case Con{+h, t}:
      grava_dicas(t, Array.set(U32, a, (OFF_DICAS() + i : U32), h), (i + 1 : U32))

# máscara dos dígitos já usados pelas dicas da linha `r`
def mascara_add(+x: U32, acc: U32, +k: U32) -> U32:
  U32.or(acc, bit_de(x))

def dicas_da_linha(+r: U32, +k: U32) -> U32:
  ((OFF_DICAS() + (r * 9 : U32) : U32) + k : U32)

# menor dígito >= d que a máscara não tem (combustível 10: `Bool.pick` é
# estrito, mas o laço é minúsculo e sempre termina)
def prox_digito(k: Nat, +mask: U32, +d: U32) -> U32:
  match k:
    case 0n:
      d
    case 1n+p:
      Bool.pick(U32, U32.is_zero(U32.and(mask, bit_de(d))), d, prox_digito(p, mask, U32.inc(d)))

# uma passada pela linha: dica fica; célula livre recebe o próximo dígito
# ausente, e o cursor `d` só anda para a frente
def preenche.um(a: Array<U32>, +base: U32, +k: U32, +mask: U32, +d: U32, +dica: U32) ->
  Array<U32> & U32:
  +vazia = U32.is_zero(dica)
  +escolhido = prox_digito(10n, mask, d)
  (Array.set(U32, a, (base + k : U32), Bool.pick(U32, vazia, escolhido, dica)),
   Bool.pick(U32, vazia, U32.inc(escolhido), d))

def preenche.rd(+d: U32, +base: U32, +k: U32, +mask: U32, r: Array<U32> & U32) ->
  Array<U32> & U32:
  (a, +dica) = r
  preenche.um(a, base, k, mask, d, dica)

def preenche.go(k: Nat, st: Array<U32> & U32, +base: U32, +i: U32, +mask: U32) -> Array<U32> & U32:
  match k:
    case 0n:
      st
    case 1n+p:
      (a, +d) = st
      preenche.go(p, preenche.rd(d, base, i, mask,
        Array.get(U32, a, ((OFF_DICAS() + base : U32) + i : U32))), base, (i + 1 : U32), mask)

# lista das colunas livres da linha, no rascunho
def livres.um(a: Array<U32>, +cnt: U32, +k: U32, +dica: U32) -> Array<U32> & U32:
  +vazia = U32.is_zero(dica)
  (Array.set(U32, a, (OFF_LIVRES() + cnt : U32), Bool.pick(U32, vazia, k, 0)),
   Bool.pick(U32, vazia, U32.inc(cnt), cnt))

def livres.rd(+cnt: U32, +k: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (a, +dica) = r
  livres.um(a, cnt, k, dica)

def livres.go(k: Nat, st: Array<U32> & U32, +base: U32, +i: U32) -> Array<U32> & U32:
  match k:
    case 0n:
      st
    case 1n+p:
      (a, +cnt) = st
      livres.go(p, livres.rd(cnt, i, Array.get(U32, a, ((OFF_DICAS() + base : U32) + i : U32))),
                base, (i + 1 : U32))

# Fisher-Yates sobre as `cnt` colunas livres listadas no rascunho
def fy.troca(+base: U32, +ci: U32, r: Array<U32> & U32) -> Array<U32>:
  (a, +cj) = r
  Arr.swap_at(~U32, a, (base + ci : U32), (base + cj : U32))

def fy.rd(+base: U32, +j: U32, r: Array<U32> & U32) -> Array<U32>:
  (a, +ci) = r
  fy.troca(base, ci, Array.get(U32, a, (OFF_LIVRES() + j : U32)))

def fy.go(k: Nat, a: Array<U32>, +base: U32, +i: U32, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      a
    case 1n+p:
      fy.go(p, fy.rd(base, R.range(seed, U32.inc(i)), Array.get(U32, a, (OFF_LIVRES() + i : U32))),
            base, (i - 1 : U32), R.step(seed))

def embaralha.if(pouco: Bool, a: Array<U32>, +cnt: U32, +base: U32, +seed: U32) -> Array<U32>:
  match pouco:
    case True{}:
      a
    case False{}:
      fy.go(U32.to_nat((cnt - 1 : U32)), a, base, (cnt - 1 : U32), seed)

def embaralha.fin(r: Array<U32> & U32, +base: U32, +seed: U32) -> Array<U32>:
  (a, +cnt) = r
  embaralha.if(U32.is_lt(cnt, 2), a, cnt, base, seed)

def init_linha.fin(r: Array<U32> & U32, +base: U32, +seed: U32) -> Array<U32>:
  (a, +d) = r
  embaralha.fin(livres.go(9n, (a, 0), base, 0), base, seed)

# a máscara sai junto com o array: o array volta pelo par, e o `init_linha`
# continua a partir dele
def init_linha.mask(r: Array<U32> & U32, +base: U32, +seed: U32) -> Array<U32>:
  (a, +mask) = r
  init_linha.fin(preenche.go(9n, (a, 1), base, 0, mask), base, seed)

def init_linha(a: Array<U32>, +r: U32, +seed: U32) -> Array<U32>:
  init_linha.mask(Arr.fold_idx(~U32, ~U32, ~dicas_da_linha, ~mascara_add, a, 0, r, 9),
                  (r * 9 : U32), seed)

def init_todas(k: Nat, a: Array<U32>, +r: U32, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      a
    case 1n+p:
      init_todas(p, init_linha(a, r, seed), (r + 1 : U32), R.split.trd(seed))

def init(+ctx: Sudoku, g: Array<U32>, +seed: U32) -> Array<U32>:
  init_todas(9n, grava_dicas(dicas_de(sud_qual(ctx)), g, 0), 0, seed)

def alloc(+ctx: Sudoku) -> Array<U32>:
  Array.new(U32, 8n, 0)

# ----------------------------------------------------------------
# MUTAÇÃO
# ----------------------------------------------------------------
# Troca duas células LIVRES da mesma linha, o que preserva a permutação da
# linha e nunca desloca uma dica. Em vez da amostragem por rejeição do TS
# (sorteia e tenta de novo até 20 vezes), monta a lista de colunas livres da
# linha no rascunho e sorteia DENTRO dela: sempre acerta na primeira, é
# uniforme de verdade, e não precisa do laço de nova tentativa — que em Bend 2
# esbarraria na falta de recursão mútua.
#
# A quantidade de trocas vem de Poisson com média `81 * taxa_por_gene`, então
# a mutação adaptativa do motor (que dobra a taxa sob estagnação) funciona.

def mut.sw(+base: U32, +c1: U32, r: Array<U32> & U32) -> Array<U32>:
  (a, +c2) = r
  Arr.swap_at(~U32, a, (base + c1 : U32), (base + c2 : U32))

def mut.rd(+base: U32, +i2: U32, r: Array<U32> & U32) -> Array<U32>:
  (a, +c1) = r
  mut.sw(base, c1, Array.get(U32, a, (OFF_LIVRES() + i2 : U32)))

def mut.pick2(poucas: Bool, a: Array<U32>, +base: U32, +cnt: U32, +seed: U32) -> Array<U32>:
  match poucas:
    case True{}:
      a
    case False{}:
      +i1 = R.range(seed, cnt)
      mut.rd(base, R.range_except(R.step(seed), cnt, i1),
             Array.get(U32, a, (OFF_LIVRES() + i1 : U32)))

def mut.pick(r: Array<U32> & U32, +base: U32, +seed: U32) -> Array<U32>:
  (a, +cnt) = r
  mut.pick2(U32.is_lt(cnt, 2), a, base, cnt, seed)

def mut.um(a: Array<U32>, +seed: U32) -> Array<U32>:
  +base = (R.range(seed, 9) * 9 : U32)
  mut.pick(livres.go(9n, (a, 0), base, 0), base, R.split.fst(seed))

def mut.go(k: Nat, a: Array<U32>, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      a
    case 1n+p:
      mut.go(p, mut.um(a, seed), R.split.trd(seed))

def mutate(+ctx: Sudoku, g: Array<U32>, +rate: U32, +seed: U32) -> Array<U32>:
  +pr = R.prob(rate)
  +lam = (pr * {81.0 : F32} : F32)
  mut.go(U32.to_nat(R.poisson(seed, lam)), g, R.split.fst(seed))

# ----------------------------------------------------------------
# CRUZAMENTO: OX1 por linha
# ----------------------------------------------------------------
# Como no TS: para cada linha, uma moeda decide entre cruzar as linhas
# correspondentes dos pais com OX1 ou copiá-las inteiras. O OX1 pode MOVER uma
# dica de lugar — é justamente o que permite escapar do ótimo local; quem
# segura a dica é o bônus da aptidão.
#
# `~key` é a identidade: o dígito 1..9 é o próprio índice da marca (por isso o
# rascunho de marcas tem 10 posições, 0..9).

def key_digito(+x: U32) -> U32:
  x

def breed_linhas.go(k: Nat, st: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>),
                    +r: U32, +cruza: Bool, +seed: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  match k:
    case 0n:
      st
    case 1n+p:
      (filhos, pais) = st
      (ca, cb) = filhos
      (pa, pb) = pais
      breed_linhas.go(p,
        Op.breed_ox1_slice(~key_digito, ca, cb, pa, pb, (r * 9 : U32), 9, OFF_MARCAS(),
          Bool.and(cruza, R.bool(R.split.fst(seed))), R.split.snd(seed)),
        (r + 1 : U32), cruza, R.split.trd(seed))

def breed(+ctx: Sudoku, ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, pb: Array<U32>,
          cruza: Bool, +seed: U32) -> (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  +c = cruza
  breed_linhas.go(9n, ((ca, cb), (pa, pb)), 0, c, seed)

# ----------------------------------------------------------------
# HASH (diversity check) — só o tabuleiro, nunca o rascunho
# ----------------------------------------------------------------
# Com `fold_range` isto é uma linha. Incluir a cauda tornaria o hash não
# determinístico, porque as marcas do OX1 são lixo de trabalho.

def hash_gene(+x: U32, acc: U32, +k: U32) -> U32:
  (U32.mul(acc, 31) + x : U32)

def hash(+ctx: Sudoku, g: Array<U32>) -> Array<U32> & U32:
  Arr.fold_range(~U32, ~U32, ~hash_gene, g, 7, 0, 81)

# ----------------------------------------------------------------
# EXIBIÇÃO
# ----------------------------------------------------------------

def cel_str(+x: U32, acc: String, +k: U32) -> String:
  acc ++ Bool.pick(String, U32.is_zero(x), ".", U32.show(x)) ++
  Bool.pick(String, Bool.or(U32.is_eq(k, 2), U32.is_eq(k, 5)), " | ", " ")

def grid.linha(+r: U32, acc: String, res: Array<U32> & String) -> Array<U32> & String:
  (a, linha) = res
  (a, acc ++ "  " ++ linha ++
     Bool.pick(String, Bool.or(U32.is_eq(r, 2), U32.is_eq(r, 5)),
               "\n  ------+-------+------\n", "\n"))

def grid.go(k: Nat, st: Array<U32> & String, +r: U32) -> Array<U32> & String:
  match k:
    case 0n:
      st
    case 1n+p:
      (a, acc) = st
      grid.go(p, grid.linha(r, acc, Arr.fold_idx(~U32, ~String, ~idx_linha, ~cel_str, a, "", r, 9)),
              (r + 1 : U32))

def grid(a: Array<U32>) -> Array<U32> & String:
  grid.go(9n, (a, ""), 0)

# ----------------------------------------------------------------
# RELATÓRIO E EXECUÇÃO
# ----------------------------------------------------------------
# Args: quadro pop_d gerações semente demes_d época diversidade max_stag
#   quadro: 0 = vazio, 1 = fácil (30 dicas), 2 = médio (32), 3 = difícil (23)

def relato.fim(r: Array<U32> & String, +bf: U32, +alvo: U32, +ndicas: U32, +gens: U32) -> String:
  (a, g) = r
  "dicas=" ++ U32.show(ndicas) ++ " gerações=" ++ U32.show(gens) ++
  " | aptidão " ++ U32.show(bf) ++ "/" ++ U32.show(alvo) ++
  Bool.pick(String, U32.is_eq(bf, alvo), "  (RESOLVIDO)", "  (não resolvido)") ++ "\n\n" ++ g

def relato(g: Array<U32>, +bf: U32, +alvo: U32, +ndicas: U32, +gens: U32) -> String:
  relato.fim(grid(g), bf, alvo, ndicas, gens)

# o campeão vive no slot 0 de `cur` depois do elitismo
def melhor.ind(r: Array<A.Individual<Array<U32>>> & A.Individual<Array<U32>>,
               +bf: U32, +alvo: U32, +ndicas: U32, +gens: U32) -> String:
  (cur, campeao) = r
  match campeao:
    case A.Individual{gene, fit, h}:
      relato(gene, bf, alvo, ndicas, gens)

def melhor.pop(p: A.Pop<Array<U32>>, +bf: U32, +alvo: U32, +ndicas: U32, +gens: U32) -> String:
  match p:
    case A.Pop{cur, nxt, h1, h2, h3, h4, size}:
      melhor.ind(Array.swap(A.Individual<Array<U32>>, cur, 0, h1), bf, alvo, ndicas, gens)

def melhor.run(run: GA.Run<Array<U32>>, +bf: U32, +alvo: U32, +ndicas: U32, +gens: U32) -> String:
  match run:
    case GA.Run{pop, bi, bfit, stag, seed}:
      melhor.pop(pop, bf, alvo, ndicas, gens)

def melhor(r: (GA.Run<Array<U32>> & Array<U32>) & U32, +alvo: U32, +ndicas: U32, +gens: U32) -> String:
  (st, +bf) = r
  (run, seen) = st
  melhor.run(run, bf, alvo, ndicas, gens)

def run(+qual: U32, +pop_d: U32, +gens: U32, +seed: U32, +demes_d: U32, +epoca: U32,
        +div: U32, +max_stag: U32, +tsize: U32) -> String:
  +ctx = sudoku_new(qual)
  +n = U32.shln(1, U32.to_nat(pop_d))
  # mesma configuração do motor em TS: 90% de cruzamento, 90% de mutação,
  # ~1 troca por tabuleiro (taxa por gene 1/81), torneio de 5
  +cfg = GA.cfg_new(R.per(9, 10), R.per(9, 10), R.per(1, 81), U32.max(tsize, 2),
                    U32.is_ne(div, 0), max_stag)
  melhor(
    GA.best_st(~Array<U32>,
      GA.archipelago(~Array<U32>, ~Sudoku, ~alloc, ~init, ~breed, ~mutate, ~fitness, ~hash,
        U32.to_nat(U32.max(U32.div(gens, U32.max(epoca, 1)), 1)), U32.to_nat(demes_d),
        GA.start_st(~Array<U32>, ~Sudoku, ~fitness,
          A.pop_new(~Array<U32>, ~Sudoku, ~alloc, ~init, U32.to_nat(pop_d), ctx, seed),
          ctx, R.step(seed)),
        ctx, cfg, U32.max(epoca, 1), n)),
    max_fitness(ctx), sud_n(ctx), gens)

def go(args: List<String>) -> IO(Unit):
  +nums = IOU.numbers(args)
  IO.print(run(IOU.num_at(nums, 0n, 0), IOU.num_at(nums, 1n, 8), IOU.num_at(nums, 2n, 1000),
               IOU.num_at(nums, 3n, 12345), IOU.num_at(nums, 4n, 0), IOU.num_at(nums, 5n, 10),
               IOU.num_at(nums, 6n, 1), IOU.num_at(nums, 7n, 50),
               IOU.num_at(nums, 8n, 5)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), go)
