import Base
import ./math.bend as M
import ./arquivos.bend as Arq

# ================================================================
# BMP (bmp.bend)
# ================================================================
# Lê e grava imagens BMP sem compressão. Na memória a imagem é uma `Imagem`:
# um pixel por slot, `0xRRGGBB`, linha 0 em cima, índice `y * largura + x`.
#
#   Bmp.ler(caminho)            -> IO(Imagem)
#   Bmp.gravar(caminho, img)    -> IO(Unit)
#   Bmp.map(~f, img)            -> Imagem       (f: 0xRRGGBB -> 0xRRGGBB)
#
# Lê BMP de 24 e 32 bits (BI_RGB), com as linhas de baixo para cima (o comum)
# ou de cima para baixo (altura negativa). Grava sempre 24 bits de baixo para
# cima, que qualquer visualizador abre.
#
# O arquivo: cabeçalho de 14 bytes + BITMAPINFOHEADER de 40, depois os
# pixels em B, G, R (e A no de 32 bits), cada linha completada com zeros até
# um múltiplo de 4 bytes.

type Imagem is Type:
  Imagem{largura: U32, altura: U32, pixels: Array<U32>}

# O que é preciso para achar um pixel dentro dos bytes do arquivo. Só
# escalares, então duplicar com `+` é barato.
type Formato is Data:
  Formato{largura: U32, altura: U32, inicio: U32, passo: U32, bpp: U32, topo: Bool}

def Formato.largura(fmt: Formato) -> U32:
  Formato{w, h, inicio, passo, bpp, topo} = fmt
  w

# ----------------------------------------------------------------
# PIXEL
# ----------------------------------------------------------------

def rgb(+r: U32, +g: U32, +b: U32) -> U32:
  U32.or(U32.or(U32.shln(r, 16n), U32.shln(g, 8n)), b)

def vermelho(+c: U32) -> U32: U32.and(U32.shrn(c, 16n), 255)
def verde(+c: U32) -> U32: U32.and(U32.shrn(c, 8n), 255)
def azul(+c: U32) -> U32: U32.and(c, 255)

# ----------------------------------------------------------------
# CABEÇALHO
# ----------------------------------------------------------------

# O cabeçalho (54 bytes) vira uma lista e é lido com `Arq.u16`/`Arq.u32`
# A altura vem com sinal: negativa quer dizer linhas de cima para baixo
def eh_negativo(+v: U32) -> Bool:
  U32.is_ge(v, 2147483648)

def modulo(+v: U32, negativo: Bool) -> U32:
  match negativo:
    case True{}: (0 - v : U32)
    case False{}: v

def formato(+h: List<&2, U32>) -> Formato:
  +w = Arq.u32(h, 18n)
  +hr = Arq.u32(h, 22n)
  +bpp = Arq.u16(h, 28n)
  # (largura * bytes por pixel), arredondado para cima até múltiplo de 4
  +passo = U32.and((w * U32.shrn(bpp, 3n) + 3 : U32), 4294967292)
  Formato{w, modulo(hr, eh_negativo(hr)), Arq.u32(h, 10n), passo, bpp, eh_negativo(hr)}

def suportado(+h: List<&2, U32>) -> Bool:
  +bpp = Arq.u16(h, 28n)
  U32.is_eq(Arq.byte(h, 0n), 66) && U32.is_eq(Arq.byte(h, 1n), 77) &&
    (U32.is_eq(bpp, 24) || U32.is_eq(bpp, 32)) &&
    U32.is_eq(Arq.u32(h, 30n), 0)

# ----------------------------------------------------------------
# LEITURA
# ----------------------------------------------------------------

def linha_fonte(topo: Bool, +y: U32, +h: U32) -> U32:
  match topo:
    case True{}: y
    case False{}: (h - 1 - y : U32)

# Onde começa o pixel (x, y) (y = 0 em cima) dentro dos bytes do arquivo
def origem(+fmt: Formato, +x: U32, +y: U32) -> U32:
  Formato{w, h, inicio, passo, bpp, topo} = fmt
  +linha = linha_fonte(topo, y, h)
  (inicio + linha * passo + x * U32.shrn(bpp, 3n) : U32)

# Três leituras encadeadas: B em `i`, G em `i+1`, R em `i+2`. Cada auxiliar
# recebe o par do `Array.get` anterior como parâmetro.
def le_px.r(r: Array<U32> & U32, +b: U32, +g: U32) -> Array<U32> & U32:
  (a, vr) = r
  (a, rgb(vr, g, b))

def le_px.g(r: Array<U32> & U32, +b: U32, +i: U32) -> Array<U32> & U32:
  (a, g) = r
  le_px.r(Array.get(U32, a, (i + 2 : U32)), b, g)

def le_px.b(r: Array<U32> & U32, +i: U32) -> Array<U32> & U32:
  (a, b) = r
  le_px.g(Array.get(U32, a, (i + 1 : U32)), b, i)

def le_px(bytes: Array<U32>, +i: U32) -> Array<U32> & U32:
  le_px.b(Array.get(U32, bytes, i), i)

def le_pixel(bytes: Array<U32>, +fmt: Formato, +p: U32) -> Array<U32> & U32:
  +w = Formato.largura(fmt)
  le_px(bytes, origem(fmt, (p % w : U32), (p / w : U32)))

# `k` pixels a partir de `p`; o par é (bytes do arquivo, pixel `p` já lido)
def decodifica.go(k: Nat, r: Array<U32> & U32, px: Array<U32>, +fmt: Formato, +p: U32) -> Array<U32>:
  match k:
    case 0n:
      (bytes, v) = r
      Array.set(U32, px, p, v)
    case 1n+q:
      (bytes, v) = r
      +prox = (p + 1 : U32)
      decodifica.go(q, le_pixel(bytes, fmt, prox), Array.set(U32, px, p, v), fmt, prox)

def decodifica(bytes: Array<U32>, +fmt: Formato) -> Imagem:
  Formato{+w, +h, inicio, passo, bpp, topo} = fmt
  +n = (w * h : U32)
  px = decodifica.go(U32.to_nat((n - 1 : U32)), le_pixel(bytes, fmt, 0), [0 : U32^M.log2_ceil(n)], fmt, 0)
  Imagem{w, h, px}

def ler.valida(ok: Bool, bytes: Array<U32>, +h: List<&2, U32>) -> IO(Imagem):
  match ok:
    case True{}:
      IO.pure(Imagem, decodifica(bytes, formato(h)))
    case False{}:
      IO.die(Imagem, 1, "BMP não suportado: só 24 ou 32 bits sem compressão")

def ler.cabecalho(r: Array<U32> & List<&2, U32>) -> IO(Imagem):
  (bytes, +h) = r
  ler.valida(suportado(h), bytes, h)

def ler.bytes(r: Array<U32> & U32) -> IO(Imagem):
  (bytes, n) = r
  ler.cabecalho(Arq.array_para_lista(bytes, 0, 54))

def ler(caminho: String) -> IO(Imagem):
  IO.bind(Array<U32> & U32, Imagem, Arq.ler_bytes(caminho), ler.bytes)

# ----------------------------------------------------------------
# ESCRITA
# ----------------------------------------------------------------

def cabecalho(a: Array<U32>, +w: U32, +h: U32, +passo: U32, +total: U32) -> Array<U32>:
  a = Array.set(U32, a, 0, 66)            # 'B'
  a = Array.set(U32, a, 1, 77)            # 'M'
  a = Arq.set_u32(a, 2, total)                # tamanho do arquivo
  a = Arq.set_u32(a, 10, 54)                  # início dos pixels
  a = Arq.set_u32(a, 14, 40)                  # tamanho do BITMAPINFOHEADER
  a = Arq.set_u32(a, 18, w)
  a = Arq.set_u32(a, 22, h)                   # positiva: de baixo para cima
  a = Arq.set_u16(a, 26, 1)                   # planos
  a = Arq.set_u16(a, 28, 24)                  # bits por pixel
  a = Arq.set_u32(a, 34, (passo * h : U32))   # tamanho dos pixels
  a = Arq.set_u32(a, 38, 2835)                # 72 dpi, em pixels por metro
  Arq.set_u32(a, 42, 2835)

def escreve_px(a: Array<U32>, +i: U32, +c: U32) -> Array<U32>:
  a = Array.set(U32, a, i, azul(c))
  a = Array.set(U32, a, (i + 1 : U32), verde(c))
  Array.set(U32, a, (i + 2 : U32), vermelho(c))

# `k` pixels a partir de `p`; o par é (pixels da imagem, pixel `p` já lido)
def codifica.go(k: Nat, r: Array<U32> & U32, out: Array<U32>, +fmt: Formato, +p: U32) -> Array<U32> & Array<U32>:
  match k:
    case 0n:
      (px, v) = r
      +w = Formato.largura(fmt)
      (px, escreve_px(out, origem(fmt, (p % w : U32), (p / w : U32)), v))
    case 1n+q:
      (px, v) = r
      +w = Formato.largura(fmt)
      +prox = (p + 1 : U32)
      out = escreve_px(out, origem(fmt, (p % w : U32), (p / w : U32)), v)
      codifica.go(q, Array.get(U32, px, prox), out, fmt, prox)

def gravar.fim(caminho: String, r: Array<U32> & Array<U32>, +total: U32) -> IO(Unit):
  (px, out) = r
  Arq.gravar_bytes(caminho, out, total)

def gravar(caminho: String, img: Imagem) -> IO(Unit):
  Imagem{+w, +h, px} = img
  +passo = U32.and((w * 3 + 3 : U32), 4294967292)
  +total = (54 + passo * h : U32)
  +fmt : Formato = Formato{w, h, 54, passo, 24, False{}}
  # o array novo é todo zero, então o enchimento no fim de cada linha já está pronto
  out = cabecalho([0 : U32^M.log2_ceil(total)], w, h, passo, total)
  gravar.fim(caminho, codifica.go(U32.to_nat((w * h - 1 : U32)), Array.get(U32, px, 0), out, fmt, 0), total)

# ----------------------------------------------------------------
# TRANSFORMAR
# ----------------------------------------------------------------

# Aplica `f` a cada pixel, no lugar. `f` recebe e devolve `0xRRGGBB`; como é
# template, a assinatura tem de ser exatamente `U32 -> U32`, sem `+`
# (Armadilha 7): se precisar reusar o pixel, faça `+c = c` dentro de `f`.
def map.go(~f: U32 -> U32, k: Nat, r: Array<U32> & U32, +p: U32) -> Array<U32>:
  match k:
    case 0n:
      (a, v) = r
      Array.set(U32, a, p, f(v))
    case 1n+q:
      (a, v) = r
      +prox = (p + 1 : U32)
      map.go(~f, q, Array.get(U32, Array.set(U32, a, p, f(v)), prox), prox)

def map(~f: U32 -> U32, img: Imagem) -> Imagem:
  Imagem{+w, +h, px} = img
  Imagem{w, h, map.go(~f, U32.to_nat((w * h - 1 : U32)), Array.get(U32, px, 0), 0)}
