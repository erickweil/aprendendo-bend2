import Base
import ./../utils/arquivos.bend as Arq

# Escreve e lê de volta um arquivo de texto e um de bytes.
#
#   bend arquivos.bend -o ../bin/arquivos && ../bin/arquivos

# Soma dos `k + 1` primeiros bytes, para conferir o que foi lido.
# O par `(array, valor)` do `Array.get` é o estado do laço.
def soma(k: Nat, r: Array<U32> & U32, +i: U32, acc: U32) -> U32:
  match k:
    case 0n:
      (arr, v) = r
      (acc + v : U32)
    case 1n+p:
      (arr, v) = r
      +prox = (i + 1 : U32)
      soma(p, Array.get(U32, arr, prox), prox, (acc + v : U32))

def mostra_bytes(r: Array<U32> & U32) -> IO(Unit):
  (arr, +n) = r
  IO.print("lidos " ++ U32.show(n) ++ " bytes, soma " ++
    U32.show(soma(U32.to_nat((n - 1 : U32)), Array.get(U32, arr, 0), 0, 0)))

# 0, 1, 2, ..., 255, 0, 1, ... (o byte de índice i é i mod 256)
def bytes_teste.go(k: Nat, arr: Array<U32>, +i: U32) -> Array<U32>:
  match k:
    case 0n:
      Array.set(U32, arr, i, U32.and(i, 255))
    case 1n+p:
      bytes_teste.go(p, Array.set(U32, arr, i, U32.and(i, 255)), (i + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    Arq.gravar_texto("/tmp/bend_teste.txt", "Olá, arquivo!\nSegunda linha: ação, ç, ã, ✓\n")
    texto : String <- Arq.ler_texto("/tmp/bend_teste.txt")
    IO.write("texto lido:\n" ++ texto)

    # 1000 bytes (0..255 repetindo), gravados e lidos de volta
    Arq.gravar_bytes("/tmp/bend_teste.bin", bytes_teste.go(999n, [0 : U32^10n], 0), 1000)
    lido : Array<U32> & U32 <- Arq.ler_bytes("/tmp/bend_teste.bin")
    mostra_bytes(lido)
