import Base
import ./../utils/io.bend as IOU
import ./../utils/arrays.bend as Arr
import ./../utils/arquivos.bend as Arq
import ./../utils/math.bend as M

# Escreve e lê de volta um arquivo de texto e um de bytes, com
# utils/arquivos.bend (que lê e grava em blocos; veja lá o porquê).
#
#   bend arquivos.bend -o ../bin/arquivos && ../bin/arquivos [n=1000]

# 0, 1, 2, ..., 255, 0, 1, ... (o byte da posição i é i mod 256)
def byte_de(v: U32, +ctx: U32, i: U32) -> U32:
  U32.and(i, 255)

def mais(+x: U32, acc: U32, +k: U32) -> U32:
  (acc + x : U32)

def soma(r: Array<U32> & U32) -> U32:
  (a, s) = r
  s

# `ler_bytes` devolve (array, quantidade): o array tem 2^k posições, e só as
# `n` primeiras são o arquivo
def mostra(r: Array<U32> & U32) -> String:
  (a, +n) = r
  "lidos " ++ U32.show(n) ++ " bytes, soma " ++ U32.show(soma(Arr.fold_range(~U32, ~U32, ~mais, a, 0, 0, n)))

# Soma de i mod 256 para i < n, para conferir
def esperado(+n: U32) -> U32:
  +voltas = (n / 256 : U32)
  +resto = (n % 256 : U32)
  (voltas * 32640 + resto * (resto - 1) / 2 : U32)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOU.num_at(IOU.numbers(args), 0n, 1000)
    Arq.gravar_texto("/tmp/bend_teste.txt", "Olá, arquivo!\nSegunda linha: ação, ç, ã, ✓\n")
    texto : String <- Arq.ler_texto("/tmp/bend_teste.txt")
    IO.write("texto lido:\n" ++ texto)

    bytes : Array<U32> = Arr.for_each(~U32, ~U32, ~byte_de, [0 : U32^M.log2_ceil(n)], 0)
    Arq.gravar_bytes("/tmp/bend_teste.bin", bytes, n)
    lido : Array<U32> & U32 <- Arq.ler_bytes("/tmp/bend_teste.bin")
    IO.print(mostra(lido) ++ " (esperado " ++ U32.show(esperado(n)) ++ ")")
