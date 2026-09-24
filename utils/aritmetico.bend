import Base
import ./math.bend as M
import ./arquivos.bend as Arq

# ================================================================
# CODIFICADOR ARITMÉTICO BINÁRIO ADAPTATIVO (aritmetico.bend)
# ================================================================
# O "range coder" do LZMA, escrito só com U32. Cada bit é codificado com uma
# probabilidade guardada num contexto, que se adapta enquanto codifica: uma
# decisão muito previsível custa uma fração de bit.
#
#   e = Enc.novo(saida, inicio)          começa a escrever em saida[inicio..]
#   e = Enc.bit(e, ctx, b)               um bit b (0/1) no contexto ctx
#   e = enc.k(e, base, k)                um inteiro com sinal (ver abaixo)
#   (saida, n) = Enc.fim(e)              esvazia; n = bytes escritos
#
#   d = Dec.novo(entrada, inicio)
#   (d, b) = Dec.bit(d, ctx)
#   (d, k) = dec.k(d, base)
#
# São 2048 contextos (índices 0..2047). Um inteiro com sinal usa um bloco de
# 128 a partir de `base`: 0 "é zero?", 1 sinal, 2..10 o prefixo unário e
# 12 + kk*8 + j o sufixo (Exp-Golomb). Representa |k| até 511.

# ----------------------------------------------------------------
# INTEIROS COM SINAL (em U32, complemento de 2)
# ----------------------------------------------------------------

def neg(+x: U32) -> Bool: U32.is_ge(x, 2147483648)

def sabs(+x: U32) -> U32:
  Bool.pick(U32, neg(x), (0 - x : U32), x)

# floor(log2 v), v >= 1
def log2_baixo(+v: U32) -> U32:
  (M.bit_count((M.next_pow2((v + 1 : U32)) - 1 : U32)) - 1 : U32)

def ctx.sufixo(+b: U32, +kk: U32, +j: U32) -> U32:
  (b + 12 + kk * 8 + j : U32)

# ----------------------------------------------------------------
# CODIFICADOR
# ----------------------------------------------------------------
# Probabilidades de 11 bits (0..2048, começando em 1024 = 50%), adaptadas em
# 1/32 a cada bit. `low` tem 33 bits no LZMA; aqui é um U32 mais um `carry`.
# `cache` é o byte que ainda pode receber o vai-um, e `pend` quantos bytes
# (o cache e uma fila de 0xFF) estão esperando por ele.

type Enc is Type:
  Enc{m: Array<U32>, out: Array<U32>, n: U32, low: U32, carry: U32, range: U32, cache: U32, pend: U32}

def preenche(k: Nat, a: Array<U32>, +i: U32, +v: U32) -> Array<U32>:
  match k:
    case 0n: a
    case 1n+p: preenche(p, Array.set(U32, a, i, v), (i + 1 : U32), v)

def Enc.shift.se(sai: Bool, m: Array<U32>, out: Array<U32>, +n: U32, +low: U32, +carry: U32, +range: U32, +cache: U32, +pend: U32) -> Enc:
  match sai:
    case True{}:
      out = Array.set(U32, out, n, U32.and((cache + carry : U32), 255))
      out = preenche(U32.to_nat((pend - 1 : U32)), out, (n + 1 : U32), U32.and((255 + carry : U32), 255))
      Enc{m, out, (n + pend : U32), U32.shln(U32.and(low, 16777215), 8n), 0, range, U32.shrn(low, 24n), 1}
    case False{}:
      Enc{m, out, n, U32.shln(U32.and(low, 16777215), 8n), 0, range, cache, (pend + 1 : U32)}

def Enc.shift(m: Array<U32>, out: Array<U32>, +n: U32, +low: U32, +carry: U32, +range: U32, +cache: U32, +pend: U32) -> Enc:
  Enc.shift.se(U32.is_lt(low, 4278190080) || U32.is_eq(carry, 1), m, out, n, low, carry, range, cache, pend)

# Com probabilidades entre ~31 e ~2017, um bit nunca derruba `range` mais que
# 8 bits abaixo de 2^24: basta um deslocamento.
def Enc.norm.se(baixo: Bool, m: Array<U32>, out: Array<U32>, +n: U32, +low: U32, +carry: U32, +range: U32, +cache: U32, +pend: U32) -> Enc:
  match baixo:
    case False{}: Enc{m, out, n, low, carry, range, cache, pend}
    case True{}: Enc.shift(m, out, n, low, carry, U32.shln(range, 8n), cache, pend)

def Enc.norm(m: Array<U32>, out: Array<U32>, +n: U32, +low: U32, +carry: U32, +range: U32, +cache: U32, +pend: U32) -> Enc:
  Enc.norm.se(U32.is_lt(range, 16777216), m, out, n, low, carry, range, cache, pend)

def Enc.bit.b(zero: Bool, m: Array<U32>, out: Array<U32>, +n: U32, +low: U32, +carry: U32, +range: U32, +cache: U32, +pend: U32, +ctx: U32, +p: U32, +bound: U32) -> Enc:
  match zero:
    case True{}:
      Enc.norm(Array.set(U32, m, ctx, (p + U32.shrn((2048 - p : U32), 5n) : U32)), out, n, low, carry, bound, cache, pend)
    case False{}:
      +nl = (low + bound : U32)
      Enc.norm(Array.set(U32, m, ctx, (p - U32.shrn(p, 5n) : U32)), out, n, nl,
        U32.or(carry, Bool.to_u32(U32.is_lt(nl, low))), (range - bound : U32), cache, pend)

def Enc.bit.p(r: Array<U32> & U32, out: Array<U32>, +n: U32, +low: U32, +carry: U32, +range: U32, +cache: U32, +pend: U32, +ctx: U32, +b: U32) -> Enc:
  (m, +p) = r
  Enc.bit.b(U32.is_zero(b), m, out, n, low, carry, range, cache, pend, ctx, p, (U32.shrn(range, 11n) * p : U32))

# Codifica o bit `b` (0 ou 1) no contexto `ctx`
def Enc.bit(e: Enc, +ctx: U32, +b: U32) -> Enc:
  Enc{m, out, n, low, carry, range, cache, pend} = e
  Enc.bit.p(Array.get(U32, m, ctx), out, n, low, carry, range, cache, pend, ctx, b)

def Enc.shift1(e: Enc) -> Enc:
  Enc{m, out, n, low, carry, range, cache, pend} = e
  Enc.shift(m, out, n, low, carry, range, cache, pend)

def Enc.fim.par(e: Enc) -> Array<U32> & U32:
  Enc{m, out, n, low, carry, range, cache, pend} = e
  (out, n)

# Esvazia o `low`: 5 deslocamentos, como no LZMA
def Enc.fim(e: Enc) -> Array<U32> & U32:
  e = Enc.shift1(Enc.shift1(Enc.shift1(Enc.shift1(Enc.shift1(e)))))
  Enc.fim.par(e)

def Enc.novo(out: Array<U32>, +n: U32) -> Enc:
  Enc{[1024 : U32^11n], out, n, 0, 0, 4294967295, 0, 1}

# ----------------------------------------------------------------
# DECODIFICADOR
# ----------------------------------------------------------------

type Dec is Type:
  Dec{m: Array<U32>, inp: Array<U32>, cur: U32, code: U32, range: U32}

def Dec.norm.le(r: Array<U32> & U32, m: Array<U32>, +cur: U32, +code: U32, +range: U32, +bit: U32) -> Dec & U32:
  (inp, +byte) = r
  (Dec{m, inp, (cur + 1 : U32), U32.or(U32.shln(code, 8n), byte), U32.shln(range, 8n)}, bit)

def Dec.norm.se(baixo: Bool, m: Array<U32>, inp: Array<U32>, +cur: U32, +code: U32, +range: U32, +bit: U32) -> Dec & U32:
  match baixo:
    case False{}: (Dec{m, inp, cur, code, range}, bit)
    case True{}: Dec.norm.le(Array.get(U32, inp, cur), m, cur, code, range, bit)

def Dec.norm(m: Array<U32>, inp: Array<U32>, +cur: U32, +code: U32, +range: U32, +bit: U32) -> Dec & U32:
  Dec.norm.se(U32.is_lt(range, 16777216), m, inp, cur, code, range, bit)

def Dec.bit.b(zero: Bool, m: Array<U32>, inp: Array<U32>, +cur: U32, +code: U32, +range: U32, +ctx: U32, +p: U32, +bound: U32) -> Dec & U32:
  match zero:
    case True{}:
      Dec.norm(Array.set(U32, m, ctx, (p + U32.shrn((2048 - p : U32), 5n) : U32)), inp, cur, code, bound, 0)
    case False{}:
      Dec.norm(Array.set(U32, m, ctx, (p - U32.shrn(p, 5n) : U32)), inp, cur, (code - bound : U32), (range - bound : U32), 1)

def Dec.bit.p(r: Array<U32> & U32, inp: Array<U32>, +cur: U32, +code: U32, +range: U32, +ctx: U32) -> Dec & U32:
  (m, +p) = r
  +bound = (U32.shrn(range, 11n) * p : U32)
  Dec.bit.b(U32.is_lt(code, bound), m, inp, cur, code, range, ctx, p, bound)

# Decodifica um bit no contexto `ctx`; devolve o estado e o bit
def Dec.bit(d: Dec, +ctx: U32) -> Dec & U32:
  Dec{m, inp, cur, code, range} = d
  Dec.bit.p(Array.get(U32, m, ctx), inp, cur, code, range, ctx)

# O primeiro byte da saída é sempre 0 (o `cache` inicial); os 4 seguintes
# enchem o `code`.
def Dec.novo.cod(r: Array<U32> & List<&2, U32>, +ini: U32) -> Dec:
  (inp, +bs) = r
  +code = U32.or(U32.or(U32.shln(Arq.byte(bs, 1n), 24n), U32.shln(Arq.byte(bs, 2n), 16n)),
                 U32.or(U32.shln(Arq.byte(bs, 3n), 8n), Arq.byte(bs, 4n)))
  Dec{[1024 : U32^11n], inp, (ini + 5 : U32), code, 4294967295}

def Dec.novo(inp: Array<U32>, +ini: U32) -> Dec:
  Dec.novo.cod(Arq.array_para_lista(inp, ini, 5), ini)

# ----------------------------------------------------------------
# UM INTEIRO k COM SINAL, EM BITS
# ----------------------------------------------------------------
# k = 0            -> 0
# k != 0           -> 1, sinal, módulo v em Exp-Golomb:
#                     kk = floor(log2 v) uns e um zero, depois os kk bits
#                     de v - 2^kk (do mais alto para o mais baixo)

def enc.prefixo(k: Nat, e: Enc, +b: U32, +j: U32) -> Enc:
  match k:
    case 0n: Enc.bit(e, (b + 2 + j : U32), 0)
    case 1n+p: enc.prefixo(p, Enc.bit(e, (b + 2 + j : U32), 1), b, (j + 1 : U32))

# `i` é o bit de `s` da vez (de kk-1 até 0); o contexto usa a posição kk-1-i
def enc.sufixo(k: Nat, e: Enc, +b: U32, +kk: U32, +s: U32, +i: U32) -> Enc:
  match k:
    case 0n: e
    case 1n+p:
      +bit = U32.and(U32.shrn(s, U32.to_nat(i)), 1)
      enc.sufixo(p, Enc.bit(e, ctx.sufixo(b, kk, (kk - 1 - i : U32)), bit), b, kk, s, (i - 1 : U32))

def enc.modulo(e: Enc, +b: U32, +v: U32) -> Enc:
  +kk = log2_baixo(v)
  e = enc.prefixo(U32.to_nat(kk), e, b, 0)
  enc.sufixo(U32.to_nat(kk), e, b, kk, (v - U32.shln(1, U32.to_nat(kk)) : U32), (kk - 1 : U32))

def enc.k.nz(zero: Bool, e: Enc, +b: U32, +k: U32) -> Enc:
  match zero:
    case True{}: e
    case False{}: enc.modulo(Enc.bit(e, (b + 1 : U32), Bool.to_u32(neg(k))), b, sabs(k))

# Codifica o inteiro com sinal `k` (|k| <= 511) no bloco de contextos `b`
def enc.k(e: Enc, +b: U32, +k: U32) -> Enc:
  enc.k.nz(U32.is_zero(k), Enc.bit(e, b, Bool.to_u32(U32.is_ne(k, 0))), b, k)

# --- a volta ---

# Lê o prefixo unário: `r` traz o bit que acabou de ser lido na posição `j`
def dec.prefixo(k: Nat, r: Dec & U32, +b: U32, +j: U32) -> Dec & U32:
  match k:
    case 0n:
      (d, bit) = r
      (d, j)
    case 1n+p:
      (d, +bit) = r
      match bit:
        case 0: (d, j)
        case _: dec.prefixo(p, Dec.bit(d, (b + 3 + j : U32)), b, (j + 1 : U32))

# Lê os kk bits do sufixo; `r` traz o bit que acabou de ser lido (posição `j`)
def dec.sufixo(k: Nat, r: Dec & U32, +b: U32, +kk: U32, +j: U32, +acc: U32) -> Dec & U32:
  match k:
    case 0n:
      (d, +bit) = r
      (d, (acc * 2 + bit : U32))
    case 1n+p:
      (d, +bit) = r
      dec.sufixo(p, Dec.bit(d, ctx.sufixo(b, kk, (j + 1 : U32))), b, kk, (j + 1 : U32), (acc * 2 + bit : U32))

def dec.modulo.soma(r: Dec & U32, +kk: U32) -> Dec & U32:
  (d, +s) = r
  (d, (U32.shln(1, U32.to_nat(kk)) + s : U32))

def dec.modulo.kk(r: Dec & U32, +b: U32) -> Dec & U32:
  (d, +kk) = r
  match kk:
    case 0: (d, 1)
    case _: dec.modulo.soma(dec.sufixo(U32.to_nat((kk - 1 : U32)), Dec.bit(d, ctx.sufixo(b, kk, 0)), b, kk, 0, 0), kk)

def dec.modulo(d: Dec, +b: U32) -> Dec & U32:
  dec.modulo.kk(dec.prefixo(10n, Dec.bit(d, (b + 2 : U32)), b, 0), b)

def dec.k.sinal(r: Dec & U32, +neg: U32) -> Dec & U32:
  (d, +v) = r
  (d, Bool.pick(U32, U32.is_eq(neg, 1), (0 - v : U32), v))

def dec.k.s(r: Dec & U32, +b: U32) -> Dec & U32:
  (d, +s) = r
  dec.k.sinal(dec.modulo(d, b), s)

def dec.k.nz(r: Dec & U32, +b: U32) -> Dec & U32:
  (d, +nz) = r
  match nz:
    case 0: (d, 0)
    case _: dec.k.s(Dec.bit(d, (b + 1 : U32)), b)

# Decodifica um inteiro com sinal do bloco de contextos `b`
def dec.k(d: Dec, +b: U32) -> Dec & U32:
  dec.k.nz(Dec.bit(d, b), b)
