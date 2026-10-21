import Base
import ./../utils/io.bend as IOU
import ./../utils/bmp.bend as Bmp

# Lê uma BMP, aplica um efeito a cada pixel e grava o resultado.
#
#   bend bmp.bend -o ../bin/bmp
#   ../bin/bmp entrada.bmp saida.bmp [efeito]
#
# (Sem uma BMP à mão? `../bin/mandelbrot 9 256 entrada.bmp` gera uma.)
#
# efeito: copia (padrão), negativo, cinza, sepia

# Os efeitos recebem e devolvem `0xRRGGBB`. Como vão para um template
# (`Bmp.map(~f, ..)`), a assinatura é `U32 -> U32` sem `+`; o `+c = c` dentro
# é o que deixa usar o pixel mais de uma vez.
def negativo(c: U32) -> U32:
  U32.xor(c, 16777215)

# Luminância (Rec. 601) em inteiros: (77 R + 150 G + 29 B) / 256
def luma(+c: U32) -> U32:
  U32.shrn((77 * Bmp.vermelho(c) + 150 * Bmp.verde(c) + 29 * Bmp.azul(c) : U32), 8n)

def cinza(c: U32) -> U32:
  +c = c
  +y = luma(c)
  Bmp.rgb(y, y, y)

def sepia(c: U32) -> U32:
  +c = c
  +y = luma(c)
  Bmp.rgb(U32.min((y + 40 : U32), 255), U32.min((y + 20 : U32), 255), y)

def aplica(efeito: String, img: Bmp.Imagem) -> Bmp.Imagem:
  match efeito:
    case "negativo": Bmp.map(~negativo, img)
    case "cinza": Bmp.map(~cinza, img)
    case "sepia": Bmp.map(~sepia, img)
    case _: img

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    +efeito : String = IOU.text_at(ts, 2n, "copia")
    img : Bmp.Imagem <- Bmp.ler(IOU.text_at(ts, 0n, "entrada.bmp"))
    Bmp.gravar(IOU.text_at(ts, 1n, "saida.bmp"), aplica(efeito, img))
    IO.print("efeito " ++ efeito ++ " aplicado")
