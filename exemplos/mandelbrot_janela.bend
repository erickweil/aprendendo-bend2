import Base
import ./../utils/io.bend as IOU
import ./../utils/math.bend as M
import ./mandelbrot.bend as Mb

# O CONJUNTO DE MANDELBROT NUMA JANELA: o botão esquerdo aproxima 2× no
# ponto clicado, o direito afasta 2×.
#
#   bend mandelbrot_janela.bend -o ../bin/mandelbrot_janela
#   ../bin/mandelbrot_janela [largura=640] [altura=480] [iterações=256]
#
# A cor de cada ponto vem de `Mb.ponto`, a função pura de mandelbrot.bend:
# o mesmo cálculo que grava o BMP desenha a janela. As iterações crescem a
# cada aproximação (`Mb.iteracoes`).
#
# A imagem só é calculada quando a vista muda (num clique) e fica guardada
# no estado; a cada quadro o `view` devolve a mesma imagem. Enquanto ela é
# calculada, a janela para de responder.
#
# Limite: F32 tem 24 bits de precisão, então por volta de 2^16 de zoom (16
# cliques) os pixels vizinhos caem no mesmo número e a imagem vira blocos.

# ----------------------------------------------------------------
# ESTADO
# ----------------------------------------------------------------
# A vista: o centro no plano complexo, o tamanho de um pixel ali, quantas
# vezes já aproximou (o zoom é 2^nivel), as iterações do zoom 1 e o tamanho
# da janela. Só números.
type Vista is Data:
  Vista{cx: F32, cy: F32, escala: F32, nivel: U32, base: U32, w: U32, h: U32}

# O estado do App: a vista e a imagem já calculada para ela
type Tela is Data:
  Tela{vista: Vista, img: Image}

# O conjunto inteiro: 3,0 de lado no menor lado da janela
def Vista.inicial(+w: U32, +h: U32, +base: U32) -> Vista:
  Vista{Mb.Centro.x(), Mb.Centro.y(), (3.0 / U32.to_f32(U32.min(w, h)) : F32), 0, base, w, h}

# O ponto do plano no centro do pixel (x, y) da janela, num eixo: `c` é o
# centro da vista e `n` o tamanho da janela nesse eixo
def eixo(+x: U32, +c: F32, +e: F32, +n: U32) -> F32:
  +meio = (U32.to_f32(n) / 2.0 : F32)
  (c + (U32.to_f32(x) + 0.5 - meio) * e : F32)

# Aproxima 2× com o centro no pixel clicado
def aproxima(v: Vista, +x: U32, +y: U32) -> Vista:
  Vista{+cx, +cy, +e, +nivel, base, +w, +h} = v
  Vista{eixo(x, cx, e, w), eixo(y, cy, e, h), (e / 2.0 : F32), (nivel + 1 : U32), base, w, h}

# Afasta 2× com o centro no pixel clicado, até voltar ao zoom 1
def afasta.se(topo: Bool, v: Vista, +x: U32, +y: U32) -> Vista:
  match topo:
    case True{}:
      v
    case False{}:
      Vista{+cx, +cy, +e, +nivel, base, +w, +h} = v
      Vista{eixo(x, cx, e, w), eixo(y, cy, e, h), (e * 2.0 : F32), (nivel - 1 : U32), base, w, h}

def Vista.nivel(+v: Vista) -> U32:
  Vista{cx, cy, e, nivel, base, w, h} = v
  nivel

def afasta(+v: Vista, +x: U32, +y: U32) -> Vista:
  afasta.se(U32.is_zero(Vista.nivel(v)), v, x, y)

def Vista.show(+v: Vista) -> String:
  Vista{cx, cy, e, +nivel, +base, w, h} = v
  "zoom 2^" ++ U32.show(nivel) ++ " em (" ++ F32.show(cx) ++ ", " ++ F32.show(cy) ++ "), " ++
    U32.show(Mb.iteracoes(base, nivel)) ++ " iterações"

# ----------------------------------------------------------------
# DESENHO: a vista vira uma árvore de quadrantes
# ----------------------------------------------------------------

def pixel(+x: U32, +y: U32, +v: Vista) -> U32:
  Vista{+cx, +cy, +e, +nivel, +base, +w, +h} = v
  Mb.ponto(eixo(x, cx, e, w), eixo(y, cy, e, h), Mb.iteracoes(base, nivel), e)

# Quatro quadrantes de uma cor só viram um `Pix` só (o interior do conjunto,
# o fundo): a árvore fica menor, e a janela desce menos níveis por pixel
def junta.pix(iguais: Bool, +a: U32, +b: U32, +c: U32, +d: U32) -> Image:
  match iguais:
    case True{}: Pix{a}
    case False{}: Qua{Pix{a}, Pix{b}, Pix{c}, Pix{d}}

def junta(a: Image, b: Image, c: Image, d: Image) -> Image:
  match a b c d:
    case Pix{+ca} Pix{+cb} Pix{+cc} Pix{+cd}:
      junta.pix(U32.is_eq(ca, cb) && U32.is_eq(ca, cc) && U32.is_eq(ca, cd), ca, cb, cc, cd)
    case qa qb qc qd:
      Qua{qa, qb, qc, qd}

def fora(+x: U32, +y: U32, +v: Vista) -> Bool:
  Vista{cx, cy, e, nivel, base, +w, +h} = v
  (x >= w : U32) || (y >= h : U32)

# Um quadrado de lado 2^n no pixel (x, y). O que fica fora da janela é um
# `Pix` só; o resto divide em quatro, em paralelo, até chegar a um pixel.
def desenha(n: Nat, vazio: Bool, +x: U32, +y: U32, +v: Vista) -> Image:
  match n vazio:
    case _ True{}:
      Pix{0}
    case 0n False{}:
      Pix{pixel(x, y, v)}
    case 1n+ +p False{}:
      +t = U32.shln(1, p)
      +x1 = (x + t : U32)
      +y1 = (y + t : U32)
      a b c d = desenha(p, fora(x, y, v), x, y, v) desenha(p, fora(x1, y, v), x1, y, v)
        desenha(p, fora(x, y1, v), x, y1, v) desenha(p, fora(x1, y1, v), x1, y1, v)
      junta(a, b, c, d)

# Uma vista nova e a imagem dela. O `!` entrega o desenho à GPU; sem GPU
# ele roda em paralelo na CPU.
def Tela.nova(+v: Vista) -> Tela:
  Vista{cx, cy, e, nivel, base, +w, +h} = v
  +k = M.log2_ceil(U32.max(w, h))
  Tela{v, desenha!(k, False{}, 0, 0, v)}

# ----------------------------------------------------------------
# O APP
# ----------------------------------------------------------------

# A cada quadro, a mesma imagem (a `Image` é `Data`: o `+` a compartilha,
# sem recalcular)
def view(t: Tela) -> Tela & Image:
  Tela{v, +img} = t
  (Tela{v, img}, img)

# Botão 0 é o esquerdo e 1 o direito. Um clique troca a vista, recalcula a
# imagem e mostra a vista nova no terminal.
def tick(eventos: List<Event>, t: Tela) -> IO(Maybe<Tela>):
  match eventos:
    case Nil{}:
      IO.pure(Maybe<Tela>, Some{t})
    case Close{} <> resto:
      IO.pure(Maybe<Tela>, None{})
    case Mouse{+x, +y, 0, True{}} <> resto:
      Tela{v, img} = t
      +v2 = aproxima(v, x, y)
      do IO<Maybe<Tela>>:
        IO.print(Vista.show(v2))
        tick(resto, Tela.nova(v2))
    case Mouse{+x, +y, 1, True{}} <> resto:
      Tela{v, img} = t
      +v2 = afasta(v, x, y)
      do IO<Maybe<Tela>>:
        IO.print(Vista.show(v2))
        tick(resto, Tela.nova(v2))
    case e <> resto:
      tick(resto, t)

def app() -> App<Tela>:
  App{view, tick}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +w : U32 = U32.clamp(IOU.num_at(ns, 0n, 640), 32, 4096)
    +h : U32 = U32.clamp(IOU.num_at(ns, 1n, 480), 32, 4096)
    +v : Vista = Vista.inicial(w, h, IOU.num_at(ns, 2n, 256))
    IO.print("botão esquerdo: aproxima 2×; direito: afasta 2×")
    IO.print(Vista.show(v))
    App.run(~Tela, ~app(), "Bend: Mandelbrot", w, h, Tela.nova(v))
