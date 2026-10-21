import Base
import ./../utils/io.bend as IOU
import ./../utils/bmp.bend as Bmp

# CONJUNTO DE MANDELBROT, calculado em paralelo e gravado como BMP.
#
# Cada pixel é independente: o trabalho ideal para paralelizar (e para a
# GPU). A imagem é montada como a árvore que um `Array` é por dentro: cada
# nível divide os pixels em duas metades e as calcula com uma chamada
# paralela, até sobrar um pixel (`ALeaf`).
#
# A cor de um ponto é uma função PURA, `ponto(cx, cy, max, px)`, que
# `mandelbrot_janela.bend` importa para desenhar numa janela.
#
#   bend mandelbrot.bend -o ../bin/mandelbrot
#   ../bin/mandelbrot [k=9: imagem 2^k x 2^k] [iterações=256] [saida.bmp] [zoom=1]
#   ../bin/mandelbrot 11 256 cavalos.bmp 150      (aproxima 150 vezes)
#   ../bin/mandelbrot 11 256 m.bmp 1 --threads 1  (compare com --threads 4, 12)
#
# A vista fica centrada no "vale dos cavalos-marinhos", entre o corpo e a
# cabeça do conjunto: com zoom 1 aparece o conjunto inteiro. As iterações
# dadas valem para o zoom 1 e crescem conforme o zoom (`iteracoes`).
#
# Medido no nativo (2048x2048, zoom 150, 928 iterações, gravando o BMP, na
# bateria): 6,2 s com 1 thread, 2,1 s com 12.

def Centro.x() -> F32: (0.0 - 0.743643887 : F32)
def Centro.y() -> F32: 0.131825904

# Quantas iterações usar num zoom de 2^nivel: o detalhe fica mais fino a
# cada aproximação, e sem mais iterações a borda vira borrão preto
def iteracoes(+base: U32, +nivel: U32) -> U32:
  (base + 96 * nivel : U32)

# ----------------------------------------------------------------
# ESCAPE
# ----------------------------------------------------------------
# Onde z <- z² + c escapou: `nu` é a contagem de passos SUAVE (fracionária)
# e `dist` estima a distância até a borda do conjunto. `nu < 0` quer dizer
# que não escapou (está dentro).
type Escape is Data:
  Escape{nu: F32, dist: F32}

# Itera z <- z² + c e também a derivada dz <- 2·z·dz + 1, até |z| > 256 ou
# acabar o combustível. Parar no meio usa o padrão da condição como
# parâmetro (`fora`), porque um `Bool.pick` calcularia a recursão de
# qualquer jeito.
#
# Contagem suave: com i passos e |z|² = m2 na saída, nu = i - log2(log2(m2))
# + 4 varia continuamente de um pixel para o outro, e acaba com as faixas
# de cor da contagem inteira (Inigo Quilez, "smooth iteration count").
# Distância: |z|·ln|z| / |dz|.
def escape(k: Nat, fora: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +dx: F32, +dy: F32, +i: U32) -> Escape:
  match k fora:
    case _ True{}:
      +m2 = (x * x + y * y : F32)
      +l2 = F32.log2(m2)
      +nu = (U32.to_f32(i) - F32.log2(l2) + 4.0 : F32)
      +razao = F32.sqrt((m2 / (dx * dx + dy * dy) : F32))
      +ln = F32.log(m2)
      Escape{nu, (0.5 * razao * ln : F32)}
    case 0n False{}:
      Escape{(0.0 - 1.0 : F32), 0.0}
    case 1n+p False{}:
      +x2 = (x * x - y * y + cx : F32)
      +y2 = (2.0 * x * y + cy : F32)
      +dx2 = (2.0 * (x * dx - y * dy) + 1.0 : F32)
      +dy2 = (2.0 * (x * dy + y * dx) : F32)
      escape(p, (x2 * x2 + y2 * y2 > 65536.0 : F32), cx, cy, x2, y2, dx2, dy2, (i + 1 : U32))

# ----------------------------------------------------------------
# CORES
# ----------------------------------------------------------------
# Um gradiente cíclico de 5 cores (o clássico do Ultra Fractal: azul escuro,
# azul, branco, laranja, quase preto), lido em t = raiz(nu) / 3: a raiz
# deixa as cores mudarem devagar onde nu é grande, perto da borda.

def parada.cor(k: U32) -> U32:
  match k:
    case 0: 1898          # (0, 7, 100)
    case 1: 2124747       # (32, 107, 203)
    case 2: 15597567      # (237, 255, 255)
    case 3: 16755200      # (255, 170, 0)
    case 4: 512           # (0, 2, 0)
    case _: 1898          # volta à primeira

def parada.pos(k: U32) -> F32:
  match k:
    case 0: 0.0
    case 1: 0.16
    case 2: 0.42
    case 3: 0.6425
    case 4: 0.8575
    case _: 1.0

def mistura(+a: U32, +b: U32, +f: F32) -> U32:
  +fa = U32.to_f32(a)
  +fb = U32.to_f32(b)
  F32.to_u32((fa + (fb - fa) * f : F32))

# Entre a parada `k` e a seguinte, na fração f
def trecho(+k: U32, +f: F32) -> U32:
  +a = parada.cor(k)
  +b = parada.cor((k + 1 : U32))
  Bmp.rgb(mistura(Bmp.vermelho(a), Bmp.vermelho(b), f), mistura(Bmp.verde(a), Bmp.verde(b), f),
    mistura(Bmp.azul(a), Bmp.azul(b), f))

def gradiente(+t0: F32) -> U32:
  +t = (t0 - F32.floor(t0) : F32)
  +k = (Bool.to_u32((t >= 0.16 : F32)) + Bool.to_u32((t >= 0.42 : F32)) +
        Bool.to_u32((t >= 0.6425 : F32)) + Bool.to_u32((t >= 0.8575 : F32)) : U32)
  +p0 = parada.pos(k)
  +p1 = parada.pos((k + 1 : U32))
  trecho(k, ((t - p0) / (p1 - p0) : F32))

def escurece(+c: U32, +luz: F32) -> U32:
  Bmp.rgb(F32.to_u32((U32.to_f32(Bmp.vermelho(c)) * luz : F32)), F32.to_u32((U32.to_f32(Bmp.verde(c)) * luz : F32)),
    F32.to_u32((U32.to_f32(Bmp.azul(c)) * luz : F32)))

# Perto da borda (a menos de ~1/4 de pixel) a cor escurece. É o que tira o
# "ruído" das regiões de detalhe: lá cada pixel cai numa cor diferente do
# gradiente, e a distância as desenha como filamentos escuros.
def cor(dentro: Bool, +nu: F32, +dist: F32, +px: F32) -> U32:
  match dentro:
    case True{}: 0
    case False{}: escurece(gradiente((F32.sqrt(nu) / 3.0 : F32)), F32.sqrt(F32.clamp((4.0 * dist / px : F32), 0.0, 1.0)))

def cor.de(e: Escape, +px: F32) -> U32:
  Escape{+nu, dist} = e
  cor((nu < 0.0 : F32), nu, dist, px)

# A COR DO PONTO c = (cx, cy), com `max` iterações; `px` é o tamanho de um
# pixel no plano (a distância é medida em pixels)
def ponto(+cx: F32, +cy: F32, +max: U32, +px: F32) -> U32:
  cor.de(escape(U32.to_nat(max), False{}, cx, cy, 0.0, 0.0, 0.0, 0.0, 0), px)

# ----------------------------------------------------------------
# A IMAGEM
# ----------------------------------------------------------------

# O pixel p de uma imagem w x w. (x0, y0) é o canto de cima à esquerda da
# vista no plano complexo, e `escala` o tamanho de um pixel ali.
def pixel(+p: U32, +w: U32, +max: U32, +x0: F32, +y0: F32, +escala: F32) -> U32:
  +cx = (x0 + (U32.to_f32((p % w : U32)) + 0.5) * escala : F32)
  +cy = (y0 + (U32.to_f32((p / w : U32)) + 0.5) * escala : F32)
  ponto(cx, cy, max, escala)

# Os 2^d pixels a partir de `ini`, as duas metades em paralelo
def pixels(d: Nat, +ini: U32, +w: U32, +max: U32, +x0: F32, +y0: F32, +escala: F32) -> Array<U32>:
  match d:
    case 0n:
      ALeaf{pixel(ini, w, max, x0, y0, escala)}
    case 1n+ +p:
      l r = pixels(p, ini, w, max, x0, y0, escala) pixels(p, (ini + U32.shln(1, p) : U32), w, max, x0, y0, escala)
      ANode{l, r}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    +k : U32 = U32.min(IOU.text_num_at(ts, 0n, 9), 13)
    +base : U32 = IOU.text_num_at(ts, 1n, 256)
    +saida : String = IOU.text_at(ts, 2n, "mandelbrot.bmp")
    +zoom : U32 = U32.max(IOU.text_num_at(ts, 3n, 1), 1)
    +max : U32 = iteracoes(base, U32.from_nat(U32.log2(zoom)))
    +w : U32 = U32.shln(1, U32.to_nat(k))
    # A vista mede 3,0 de lado, dividido pelo zoom, em volta do centro
    +lado : F32 = (3.0 / U32.to_f32(zoom) : F32)
    +escala : F32 = (lado / U32.to_f32(w) : F32)
    +x0 : F32 = (Centro.x() - lado / 2.0 : F32)
    +y0 : F32 = (Centro.y() - lado / 2.0 : F32)
    t0 : Nat <- IO.now()
    # `!` entrega a chamada à GPU; sem GPU (ou com --gpu off) roda na CPU
    img : Bmp.Imagem = Bmp.Imagem{w, w, pixels!(U32.to_nat((2 * k : U32)), 0, w, max, x0, y0, escala)}
    Bmp.gravar(saida, img)
    dt : String <- IOU.tempo_desde(t0)
    IO.print(U32.show(w) ++ "x" ++ U32.show(w) ++ ", zoom " ++ U32.show(zoom) ++ ", " ++ U32.show(max) ++ " iterações -> " ++ saida ++ " (" ++ dt ++ ")")
