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
#   ../bin/mandelbrot [k=9: imagem 2^k x 2^k] [iterações=256] [saida.bmp]
#   ../bin/mandelbrot 11 1000 --threads 1      (compare com --threads 4, 12)
#
# Medido no nativo (2048x2048, 1000 iterações, gravando o BMP): 2,0 s com 1
# thread, 0,85 s com 4 e 0,51 s com 12 (3,9×, o teto desta máquina).

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

# Paleta: preto dentro do conjunto; fora, de azul a amarelo conforme a raiz
# de i/max (a raiz realça as bordas, onde i é pequeno)
def cor(+i: U32, +max: U32) -> U32:
  +f = F32.sqrt((U32.to_f32(i) / U32.to_f32(max) : F32))
  +t = F32.to_u32((f * 255.0 : F32))
  Bool.pick(U32, (i >= max : U32), 0, Bmp.rgb(U32.min((t * 3 : U32), 255), t, (255 - t : U32)))

# O pixel p de uma imagem w x w, com a vista centrada em (-0,6; 0) e 3,0 de
# largura. (Os nomes locais saem de dentro das anotações de F32.)
def pixel(+p: U32, +w: U32, +max: U32) -> U32:
  +escala = (3.0 / U32.to_f32(w) : F32)
  +px = U32.to_f32((p % w : U32))
  +py = U32.to_f32((p / w : U32))
  +cx = (px * escala - 2.1 : F32)
  +cy = (py * escala - 1.5 : F32)
  cor(escape(U32.to_nat(max), False{}, cx, cy, 0.0, 0.0, 0), max)

# Os 2^d pixels a partir de `ini`, as duas metades em paralelo
def pixels(d: Nat, +ini: U32, +w: U32, +max: U32) -> Array<U32>:
  match d:
    case 0n:
      ALeaf{pixel(ini, w, max)}
    case 1n+ +p:
      l r = pixels(p, ini, w, max) pixels(p, (ini + U32.shln(1, p) : U32), w, max)
      ANode{l, r}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    +k : U32 = U32.min(IOU.text_num_at(ts, 0n, 9), 13)
    +max : U32 = IOU.text_num_at(ts, 1n, 256)
    +saida : String = IOU.text_at(ts, 2n, "mandelbrot.bmp")
    +w : U32 = U32.shln(1, U32.to_nat(k))
    t0 : Nat <- IO.now()
    # `!` entrega a chamada à GPU; sem GPU (ou com --gpu off) roda na CPU
    img : Bmp.Imagem = Bmp.Imagem{w, w, pixels!(U32.to_nat((2 * k : U32)), 0, w, max)}
    Bmp.gravar(saida, img)
    dt : String <- IOU.tempo_desde(t0)
    IO.print(U32.show(w) ++ "x" ++ U32.show(w) ++ ", " ++ U32.show(max) ++ " iterações -> " ++ saida ++ " (" ++ dt ++ ")")
