import Base
import ./../utils/io.bend as IOU

# UMA JANELA ANIMADA com `App.run`: uma bola quica pela tela; qualquer tecla
# troca a cor e um clique leva a bola até o mouse.
#
# Gráficos em Bend são PUROS: um quadro é uma `Image`, e o App só diz como
# o estado vira imagem (`view`) e como os eventos mudam o estado (`tick`):
#
#   type Image is Data:
#     Pix{color: U32}                               # um quadrado de uma cor
#     Qua{tl: Image, tr: Image, bl: Image, br: Image}  # dividido em quatro
#
#   App{view: S -> (S, Image), tick: List<Event> -> S -> IO(Maybe<S>)}
#
# `tick` devolve `None` para fechar. `App.play` roda o mesmo App SEM janela,
# com eventos escritos à mão: é assim que se testa um App.
#
#   bend janela.bend -o ../bin/janela        (no Linux precisa de libx11-dev)
#   ../bin/janela [quadros=0: até fechar]
#   ../bin/janela teste                      (sem janela, com App.play)

def Tela.lado() -> U32: 256
def Bola.lado() -> U32: 32

type Bola is Data:
  Bola{x: U32, y: U32, dx: U32, dy: U32, cor: U32, quadros: U32, limite: U32}

# Uma cor por índice (0..3)
def cores(i: U32) -> U32:
  match i:
    case 0: 16739179      # laranja
    case 1: 5025616       # verde
    case 2: 4367861       # azul
    case _: 16761095      # amarelo

# ----------------------------------------------------------------
# VIEW: o estado vira uma quadtree
# ----------------------------------------------------------------
def fundo() -> U32: 1315860

# O quadrado [x0, x0 + t) x [y0, y0 + t) está todo fora da bola? Todo dentro?
def fora(+x0: U32, +y0: U32, +t: U32, +bx: U32, +by: U32) -> Bool:
  (x0 + t <= bx : U32) || (bx + Bola.lado() <= x0 : U32) || (y0 + t <= by : U32) || (by + Bola.lado() <= y0 : U32)

def dentro(+x0: U32, +y0: U32, +t: U32, +bx: U32, +by: U32) -> Bool:
  (bx <= x0 : U32) && (x0 + t <= bx + Bola.lado() : U32) && (by <= y0 : U32) && (y0 + t <= by + Bola.lado() : U32)

# Todo fora: um `Pix` de fundo. Todo dentro: um `Pix` da cor. Senão divide
# em quatro, e os quadrantes saem de dois pares de chamadas paralelas. Como
# `desenha` não pode chamar um auxiliar que a chame de volta, quem calcula
# `fora`/`dentro` de cada quadrante é quem o pede (padrão da Armadilha 2).
def desenha(k: Nat, e_fora: Bool, e_dentro: Bool, +x0: U32, +y0: U32, +t: U32, +bx: U32, +by: U32, +cor: U32) -> Image:
  match k e_fora e_dentro:
    case _ True{} _: Pix{fundo()}
    case _ False{} True{}: Pix{cor}
    case 0n False{} False{}: Pix{cor}
    case 1n+ +p False{} False{}:
      +h = (t / 2 : U32)
      +x1 = (x0 + h : U32)
      +y1 = (y0 + h : U32)
      tl tr =
        desenha(p, fora(x0, y0, h, bx, by), dentro(x0, y0, h, bx, by), x0, y0, h, bx, by, cor)
        desenha(p, fora(x1, y0, h, bx, by), dentro(x1, y0, h, bx, by), x1, y0, h, bx, by, cor)
      bl br =
        desenha(p, fora(x0, y1, h, bx, by), dentro(x0, y1, h, bx, by), x0, y1, h, bx, by, cor)
        desenha(p, fora(x1, y1, h, bx, by), dentro(x1, y1, h, bx, by), x1, y1, h, bx, by, cor)
      Qua{tl, tr, bl, br}

def view(b: Bola) -> Image:
  Bola{+x, +y, dx, dy, c, q, l} = b
  desenha(8n, False{}, False{}, 0, 0, Tela.lado(), x, y, cores((c % 4 : U32)))

# ----------------------------------------------------------------
# TICK: os eventos do quadro mudam o estado
# ----------------------------------------------------------------
# Rebate na parede: se o próximo passo sai da tela, inverte a direção
# (a direção é +1 ou -1, que em U32 é 4294967295)
def rebate(+p: U32, +d: U32) -> U32:
  Bool.pick(U32, ((p + d : U32) > (Tela.lado() - Bola.lado()) : U32), (0 - d : U32), d)

# Um passo de animação; `None` fecha a janela quando chega no limite
def anda(b: Bola) -> Maybe<&1, Bola>:
  Bola{+x, +y, dx, dy, c, +q, +lim} = b
  +dx2 = rebate(x, dx)
  +dy2 = rebate(y, dy)
  Bool.pick(Maybe<&1, Bola>, U32.is_ne(lim, 0) && (q + 1 >= lim : U32), None{},
    Some{Bola{(x + dx2 : U32), (y + dy2 : U32), dx2, dy2, c, (q + 1 : U32), lim}})

def troca_cor(b: Bola) -> Bola:
  Bola{x, y, dx, dy, c, q, l} = b
  Bola{x, y, dx, dy, (c + 1 : U32), q, l}

def leva_para(b: Bola, +mx: U32, +my: U32) -> Bola:
  Bola{x, y, dx, dy, c, q, l} = b
  +m = (Tela.lado() - Bola.lado() : U32)
  Bola{U32.min(mx, m), U32.min(my, m), dx, dy, c, q, l}

def tick(eventos: List<Event>, b: Bola) -> IO(Maybe<&1, Bola>):
  match eventos:
    case Nil{}:
      IO.pure(Maybe<&1, Bola>, anda(b))
    case Close{} <> resto:
      IO.pure(Maybe<&1, Bola>, None{})
    case Key{codigo, True{}} <> resto:
      tick(resto, troca_cor(b))
    case Mouse{mx, my, botao, True{}} <> resto:
      tick(resto, leva_para(b, mx, my))
    case e <> resto:
      tick(resto, b)

def app() -> App<Bola>:
  App{+b => (b, view(b)), tick}

def inicio(+limite: U32) -> Bola:
  Bola{10, 50, 3, 2, 0, 0, limite}

# ----------------------------------------------------------------
# SEM JANELA: App.play com eventos escritos à mão
# ----------------------------------------------------------------
def roteiro() -> List<&1, List<&1, Event>>:
  [[], [Key{32, True{}}], [], [Mouse{200, 10, 1, True{}}], [], []]

def mostra(m: Maybe<&1, Bola>) -> String:
  match m:
    case None{}: "a janela teria fechado"
    case Some{b}:
      match b:
        case Bola{x, y, dx, dy, c, q, l}:
          "depois de " ++ U32.show(q) ++ " quadros: bola em (" ++ U32.show(x) ++ ", " ++ U32.show(y) ++ "), cor " ++ U32.show(c)

def executa(modo: String, +quadros: U32) -> IO(Unit):
  match modo:
    case "teste":
      do IO<Unit>:
        final : Maybe<&1, Bola> <- App.play(~Bola, ~app(), roteiro(), inicio(0))
        IO.print(mostra(final))
    case _:
      App.run(~Bola, ~app(), "Bend: bola quicando", Tela.lado(), Tela.lado(), inicio(quadros))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    executa(IOU.text_at(ts, 0n, ""), IOU.text_num_at(ts, 0n, 0))
