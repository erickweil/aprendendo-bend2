import Base
import ./../utils/io.bend as IOU
import ./../utils/math.bend as M

# UMA ESFERA QUICANDO numa janela: ela anda em linha reta e, ao tocar uma
# borda, a velocidade daquele eixo troca de sinal. Sem teclado nem mouse.
#
#   bend janela.bend -o ../bin/janela        (no Linux precisa de libx11-dev)
#   ../bin/janela [largura=640] [altura=480] [quadros=0: até fechar]
#
# Gráficos em Bend são PUROS. Um quadro é uma `Image`, uma árvore de
# quadrantes, e o App só diz como o estado vira imagem e como ele avança:
#
#   type Image is Data:
#     Pix{color: U32}                                  # um quadrado de uma cor
#     Qua{tl: Image, tr: Image, bl: Image, br: Image}  # dividido em quatro
#
#   App{view: S -> (S, Image), tick: List<Event> -> S -> IO(Maybe<S>)}
#
# A raiz da árvore é um quadrado de lado 2^k que cobre a janela, com o canto
# no topo à esquerda; o que passa da largura ou da altura não aparece. A
# janela mostra no máximo 60 quadros por segundo.
#
# Medido no nativo (i5-1245U, sem GPU, 2.0.29): 640x480 fica nos 60 quadros
# por segundo; 1280x720 dá ~50 e 1920x1080 ~35, com 1 ou 12 threads. Montar
# a árvore custa só ~4,6 ms por quadro em 1080p; o que pesa é o
# `Window.frame` no Linux, que desce a árvore uma vez POR PIXEL da janela,
# numa thread só (uma imagem fixa de um nível já o deixa em ~48 em 1080p).

# ----------------------------------------------------------------
# ESTADO
# ----------------------------------------------------------------
# Posição do centro e velocidade em pixels por quadro, em F32 para o
# movimento ser suave; o raio; e o tamanho da janela. Só números: o estado
# inteiro viaja em registradores de chamada em chamada.
type Bola is Data:
  Bola{x: F32, y: F32, vx: F32, vy: F32, r: F32, w: U32, h: U32}

# O raio é 1/8 do menor lado; a velocidade depende do tamanho da janela
# (atravessa a largura em ~3 s), com proporções diferentes em x e em y para
# a esfera não repetir sempre a mesma diagonal.
def inicio(+w: U32, +h: U32) -> Bola:
  +fw = U32.to_f32(w)
  +fh = U32.to_f32(h)
  Bola{(fw / 3.0 : F32), (fh / 4.0 : F32), (fw / 180.0 : F32), (fh / 140.0 : F32),
    U32.to_f32((U32.min(w, h) / 8 : U32)), w, h}

# ----------------------------------------------------------------
# MOVIMENTO
# ----------------------------------------------------------------

# Um seletor tipado: com `match`, só o valor escolhido é usado, e ele não
# "encaixota" o F32 como o `Bool.pick` genérico faz (bend guide shaders).
def escolhe(c: Bool, a: F32, b: F32) -> F32:
  match c:
    case True{}: a
    case False{}: b

# A nova velocidade num eixo, depois de andar até `q`: se passou da parede
# de baixo (0), vai para o lado positivo; se passou da de cima (lim), para o
# negativo; senão continua a mesma. Refletir é só isso.
def reflete(+q: F32, +v: F32, +r: F32, +lim: F32) -> F32:
  escolhe((q < r : F32), F32.abs(v),
    escolhe((q > lim - r : F32), (0.0 - F32.abs(v) : F32), v))

# Um quadro de animação: anda, prende a esfera dentro da janela e reflete
def anda(b: Bola) -> Bola:
  Bola{+x, +y, +vx, +vy, +r, +w, +h} = b
  +fw = U32.to_f32(w)
  +fh = U32.to_f32(h)
  +nx = (x + vx : F32)
  +ny = (y + vy : F32)
  Bola{F32.clamp(nx, r, (fw - r : F32)), F32.clamp(ny, r, (fh - r : F32)),
    reflete(nx, vx, r, fw), reflete(ny, vy, r, fh), r, w, h}

# ----------------------------------------------------------------
# DESENHO: o estado vira uma árvore de quadrantes
# ----------------------------------------------------------------

def Cor.fundo() -> U32: 1579040    # 0x181820

def rgb(+r: U32, +g: U32, +b: U32) -> U32:
  U32.or(U32.or(U32.shln(r, 16n), U32.shln(g, 8n)), b)

# Um canal: a cor base vezes a luz difusa, mais o brilho branco (até 255)
def canal(+base: F32, +difusa: F32, +brilho: F32) -> U32:
  F32.to_u32(F32.min((base * difusa + 255.0 * brilho : F32), 255.0))

# A cor de um ponto da esfera, com (dx, dy) em unidades de raio a partir do
# centro. A normal ali é (dx, dy, dz), com dz = raiz(1 - dx² - dy²). A luz vem
# de cima à esquerda, da direção (-0,45; -0,55; 0,70): o brilho difuso é o
# cosseno entre ela e a normal, e o reflexo é esse cosseno elevado a 40 (uma
# mancha pequena e forte).
def sombreia(+dx: F32, +dy: F32) -> U32:
  +dz = F32.sqrt(F32.max((1.0 - dx * dx - dy * dy : F32), 0.0))
  +luz = F32.max((0.70 * dz - 0.45 * dx - 0.55 * dy : F32), 0.0)
  +difusa = (0.15 + 0.85 * luz : F32)
  +brilho = F32.pow(luz, 40.0)
  rgb(canal(255.0, difusa, brilho), canal(110.0, difusa, brilho), canal(40.0, difusa, brilho))

def pixel.cor(dentro: Bool, +dx: F32, +dy: F32) -> U32:
  match dentro:
    case True{}: sombreia(dx, dy)
    case False{}: Cor.fundo()

# Um pixel: o centro dele cai dentro do disco?
def pixel(+x: U32, +y: U32, +cx: F32, +cy: F32, +r: F32) -> U32:
  +dx = ((U32.to_f32(x) + 0.5 - cx) / r : F32)
  +dy = ((U32.to_f32(y) + 0.5 - cy) / r : F32)
  pixel.cor((dx * dx + dy * dy < 1.0 : F32), dx, dy)

# O quadrado de lado `t` em (x0, y0) fica todo fora do disco? Compara o raio
# com a distância do centro até o ponto do quadrado mais perto dele. O que
# está fora da janela também fica fora do disco, então é cortado aqui.
def fora(+x0: U32, +y0: U32, +t: U32, +cx: F32, +cy: F32, +r: F32) -> Bool:
  +ax = U32.to_f32(x0)
  +ay = U32.to_f32(y0)
  +bx = (ax + U32.to_f32(t) : F32)
  +by = (ay + U32.to_f32(t) : F32)
  +dx = (F32.clamp(cx, ax, bx) - cx : F32)
  +dy = (F32.clamp(cy, ay, by) - cy : F32)
  (dx * dx + dy * dy >= r * r : F32)

# Um quadrado de lado 2^n. Todo fora: um `Pix` só, com a cor do fundo, sem
# descer mais. Senão divide em quatro, calculados em paralelo, até chegar a
# um pixel. Por isso o custo de um quadro é proporcional ao tamanho da
# esfera, não ao da janela. Quem pede cada quadrante já calcula se ele está
# `vazio` (a condição vira parâmetro: `desenha` não pode chamar um auxiliar
# que a chame de volta).
def desenha(n: Nat, vazio: Bool, +x0: U32, +y0: U32, +cx: F32, +cy: F32, +r: F32) -> Image:
  match n vazio:
    case _ True{}:
      Pix{Cor.fundo()}
    case 0n False{}:
      Pix{pixel(x0, y0, cx, cy, r)}
    case 1n+ +p False{}:
      +t = U32.shln(1, p)
      +x1 = (x0 + t : U32)
      +y1 = (y0 + t : U32)
      a b c d = desenha(p, fora(x0, y0, t, cx, cy, r), x0, y0, cx, cy, r)
        desenha(p, fora(x1, y0, t, cx, cy, r), x1, y0, cx, cy, r)
        desenha(p, fora(x0, y1, t, cx, cy, r), x0, y1, cx, cy, r)
        desenha(p, fora(x1, y1, t, cx, cy, r), x1, y1, cx, cy, r)
      Qua{a, b, c, d}

# O `view` devolve o estado ao lado da imagem (o estado é afim: quem o
# recebe precisa devolvê-lo). O `!` entrega o desenho à GPU; sem GPU ele roda
# em paralelo na CPU.
def view(b: Bola) -> Bola & Image:
  Bola{+x, +y, vx, vy, +r, +w, +h} = b
  +k = M.log2_ceil(U32.max(w, h))
  (Bola{x, y, vx, vy, r, w, h}, desenha!(k, fora(0, 0, U32.shln(1, k), x, y, r), 0, 0, x, y, r))

# ----------------------------------------------------------------
# O APP
# ----------------------------------------------------------------

# Os eventos do quadro: só o fechar da janela interessa. `None` encerra.
def tick(eventos: List<Event>, b: Bola) -> IO(Maybe<Bola>):
  match eventos:
    case Nil{}:
      IO.pure(Maybe<Bola>, Some{anda(b)})
    case Close{} <> resto:
      IO.pure(Maybe<Bola>, None{})
    case e <> resto:
      tick(resto, b)

def app() -> App<Bola>:
  App{view, tick}

# `App.run` é `Window.open` seguido de `App.loop` com um combustível de 2^32
# quadros (~2 anos a 60 por segundo). Aqui o `App.loop` é chamado direto
# para aceitar um número de quadros; 0 é "até fechar".
def quadros(n: U32) -> Nat:
  match n:
    case 0: U32.to_nat(4294967295)
    case k: U32.to_nat(k)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +w : U32 = U32.clamp(IOU.num_at(ns, 0n, 640), 32, 4096)
    +h : U32 = U32.clamp(IOU.num_at(ns, 1n, 480), 32, 4096)
    +n : U32 = IOU.num_at(ns, 2n, 0)
    janela : Window <- IO.try(Window, Window.open("Bend: esfera", w, h))
    t0 : Nat <- IO.now()
    App.loop(~Bola, ~app(), quadros(n), janela, inicio(w, h))
    dt : String <- IOU.tempo_desde(t0)
    IO.print(U32.show(n) ++ " quadros de " ++ U32.show(w) ++ "x" ++ U32.show(h) ++ " em " ++ dt)
