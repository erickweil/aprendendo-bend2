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
#   bend mandelbrot.bend -o ../bin/mandelbrot
#   ../bin/mandelbrot [k=9: imagem 2^k x 2^k] [iterações=256] [saida.bmp] [zoom=1]
#   ../bin/mandelbrot 11 1000 cavalos.bmp 150      (aproxima 150 vezes)
#   ../bin/mandelbrot 11 1000 m.bmp 1 --threads 1  (compare com --threads 4, 12)
#
# A vista fica centrada no "vale dos cavalos-marinhos", entre o corpo e a
# cabeça do conjunto: com zoom 1 aparece o conjunto inteiro.
#
# Medido no nativo (2048x2048, 1000 iterações, zoom 1, gravando o BMP): 3,8×
# mais rápido com 12 threads que com 1 (4,2 s -> 1,1 s, com o notebook na
# bateria; na tomada tudo leva cerca de metade).

def Centro.x() -> F32: (0.0 - 0.743643887 : F32)
def Centro.y() -> F32: 0.131825904

# z <- z² + c até |z| > 2 ou acabar o combustível; devolve quantos passos.
# Parar no meio usa o padrão da condição como parâmetro (`fora`), porque um
# `Bool.pick` calcularia a recursão de qualquer jeito.
def escape(k: Nat, fora: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +i: U32) -> U32:
  match k fora:
    case _ True{}: i
    case 0n False{}: i
    case 1n+p False{}:
      +x2 = (x * x - y * y + cx : F32)
      +y2 = (2.0 * x * y + cy : F32)
      escape(p, (x2 * x2 + y2 * y2 > 4.0 : F32), cx, cy, x2, y2, (i + 1 : U32))

# Um canal de 0 a 255 que sobe e desce como um cosseno: dá uma volta a cada
# 256 unidades de `i * freq + fase`
def onda(+i: U32, +freq: U32, +fase: U32) -> U32:
  +t = U32.to_f32(((i * freq + fase) % 256 : U32))
  F32.to_u32(((0.5 + 0.5 * F32.cos((t / 256.0 * 2.0 * F32.pi() : F32))) * 255.0 : F32))

# Paleta: preto dentro do conjunto; fora, uma onda por canal, com
# frequências e fases diferentes sobre o número de passos. As cores mudam
# devagar com `i` (tons de roxo, rosa, amarelo e verde que se repetem).
def cor(dentro: Bool, +i: U32) -> U32:
  match dentro:
    case True{}: 0
    case False{}: Bmp.rgb(onda(i, 4, 0), onda(i, 6, 128), onda(i, 2, 0))

# O pixel p de uma imagem w x w. (x0, y0) é o canto de cima à esquerda da
# vista no plano complexo, e `escala` o tamanho de um pixel ali.
def pixel(+p: U32, +w: U32, +max: U32, +x0: F32, +y0: F32, +escala: F32) -> U32:
  +cx = (x0 + U32.to_f32((p % w : U32)) * escala : F32)
  +cy = (y0 + U32.to_f32((p / w : U32)) * escala : F32)
  +i = escape(U32.to_nat(max), False{}, cx, cy, 0.0, 0.0, 0)
  cor((i >= max : U32), i)

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
    +max : U32 = IOU.text_num_at(ts, 1n, 256)
    +saida : String = IOU.text_at(ts, 2n, "mandelbrot.bmp")
    +zoom : U32 = U32.max(IOU.text_num_at(ts, 3n, 1), 1)
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
    IO.print(U32.show(w) ++ "x" ++ U32.show(w) ++ ", " ++ U32.show(max) ++ " iterações, zoom " ++ U32.show(zoom) ++ " -> " ++ saida ++ " (" ++ dt ++ ")")
