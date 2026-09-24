import Base
import ./math.bend as M

# ================================================================
# ARQUIVOS (arquivos.bend)
# ================================================================
# A Base expõe o arquivo como um `File` afim: todo efeito sobre ele devolve
# o handle de volta junto com um `Result`, `IO(File & Result<.., A>)`. Aqui
# estão as formas de lidar com isso sem repetir o tratamento de erro:
#
#   abrir(caminho, "r")        -> IO(File)             (morre se falhar)
#   tentar(A, File.size(f))    -> IO(File & A)         (morre se falhar)
#
# e as operações de alto nível:
#
#   ler_texto(caminho)                -> IO(String)
#   gravar_texto(caminho, texto)      -> IO(Unit)
#   ler_bytes(caminho)                -> IO(Array<U32> & U32)   (bytes, quantidade)
#   gravar_bytes(caminho, bytes, n)   -> IO(Unit)
#
# Um byte é um `U32` de 0 a 255, como na Base. O array lido tem 2^k slots
# (a menor potência de 2 que cabe o arquivo); a quantidade real vem ao lado.
#
# POR QUE EM BLOCOS. `File.read_bytes` e `File.write_bytes` trocam os bytes
# como `List<&2, U32>`, uma célula por byte. Medido no nativo (2.0.26,
# i5-1245U, arquivo de 64 MB, --threads 1):
#
#   ler o arquivo inteiro numa lista só        1,15 s   1,8 GB de pico
#   ler em blocos de 64 KB..256 KB             1,0 s    265 MB
#   ler em blocos de 1 MB (o padrão aqui)      0,78 s   290 MB
#   ler em blocos de 4 MB                      0,73 s   370 MB
#   gravar numa lista só                       ~1,1 s   1,9 GB
#   gravar em blocos de 1 MB                   ~0,55 s  290 MB
#
# A lista inteira custa ~28 bytes de memória por byte do arquivo; em blocos
# fica o `Array` (4 bytes por slot) mais um bloco. Em blocos de 1 MB são
# ~12 ns por byte lido e ~8 ns por byte gravado: 3 MB (uma imagem 1024x1024)
# em ~40 ms.

# ----------------------------------------------------------------
# ERROS
# ----------------------------------------------------------------

def abrir(caminho: String, modo: String) -> IO(File):
  IO.try(File, File.open(caminho, modo))

# Tira o valor do `Result`, mantendo o handle. Num erro o programa termina com
# a mensagem do sistema (como o `IO.try`); o handle é descartado junto.
def solta(-A: Type, r: File & Result<&1, &1, U32 & String, A>) -> IO(File & A):
  (f, res) = r
  match res:
    case Done{v}:
      IO.pure(File & A, (f, v))
    case Fail{(code, msg)}:
      IO.die(File & A, code, msg)

def tentar(-A: Type, act: IO(File & Result<&1, &1, U32 & String, A>)) -> IO(File & A):
  IO.bind(File & Result<&1, &1, U32 & String, A>, File & A, act, solta(A))

# ----------------------------------------------------------------
# TEXTO
# ----------------------------------------------------------------

def ler_texto.leu(r: File & String) -> IO(String):
  (f, s) = r
  do IO<String>:
    File.close(f)
    return s

def ler_texto.tamanho(r: File & U32) -> IO(String):
  (f, n) = r
  IO.bind(File & String, String, tentar(String, File.read(f, n)), ler_texto.leu)

def ler_texto(caminho: String) -> IO(String):
  do IO<String>:
    f : File <- abrir(caminho, "r")
    r : File & U32 <- tentar(U32, File.size(f))
    ler_texto.tamanho(r)

def fecha(r: File & Unit) -> IO(Unit):
  (f, u) = r
  File.close(f)

def gravar_texto(caminho: String, texto: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- abrir(caminho, "w")
    r : File & Unit <- tentar(Unit, File.write(f, texto))
    fecha(r)

# ----------------------------------------------------------------
# LISTA <-> ARRAY
# ----------------------------------------------------------------

# Os `k + 1` bytes de `i - k` até `i`, como lista. Vai de trás para frente
# para montar a lista com `Con` sem inverter. O par `(array, valor)` do
# `Array.get` é o estado do laço (Armadilha 3b).
def array_para_lista.go(k: Nat, r: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match k:
    case 0n:
      (arr, v) = r
      (arr, Con{v, acc})
    case 1n+p:
      (arr, v) = r
      +prev = (i - 1 : U32)
      array_para_lista.go(p, Array.get(U32, arr, prev), prev, Con{v, acc})

# Os `n` bytes a partir de `ini`, como lista (n >= 1)
def array_para_lista(arr: Array<U32>, +ini: U32, +n: U32) -> Array<U32> & List<&2, U32>:
  +fim = (ini + n - 1 : U32)
  array_para_lista.go(U32.to_nat((n - 1 : U32)), Array.get(U32, arr, fim), fim, Nil{})

# ----------------------------------------------------------------
# BYTES: LEITURA
# ----------------------------------------------------------------

# Copia a lista para o array a partir de `i` (sem devolver o índice final)
def copia(xs: List<&2, U32>, arr: Array<U32>, +i: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      arr
    case Con{h, t}:
      copia(t, Array.set(U32, arr, i, h), (i + 1 : U32))

# Lê em blocos de `bloco` bytes com `File.read_at`, cada um copiado para
# o array antes de ler o próximo (a lista nunca passa de um bloco). O bloco
# recém-lido é o estado do laço: `k` conta os blocos que faltam ler.
def ler_blocos.go(k: Nat, lido: File & List<&2, U32>, arr: Array<U32>, +bloco: U32, +pos: U32) -> IO(Array<U32>):
  match k:
    case 0n:
      (f, xs) = lido
      do IO<Array<U32>>:
        File.close(f)
        return copia(xs, arr, pos)
    case 1n+p:
      (f, xs) = lido
      +prox = (pos + bloco : U32)
      arr = copia(xs, arr, pos)
      IO.bind(File & List<&2, U32>, Array<U32>,
        tentar(List<&2, U32>, File.read_at(f, prox, bloco)),
        l => ler_blocos.go(p, l, arr, bloco, prox))

# Arquivo vazio: `k` abaixo daria a volta (0 - 1), então é tratado à parte.
def ler_blocos.vazio(f: File) -> IO(Array<U32> & U32):
  do IO<Array<U32> & U32>:
    File.close(f)
    return ([0 : U32^0n], 0)

def ler_blocos.cheio(f: File, +n: U32, +bloco: U32) -> IO(Array<U32> & U32):
  # blocos = ceil(n / bloco), no mínimo 1; `k` é quantos faltam depois do primeiro
  +k = U32.to_nat(((n + bloco - 1 : U32) / bloco - 1 : U32))
  IO.bind(File & List<&2, U32>, Array<U32> & U32,
    tentar(List<&2, U32>, File.read_at(f, 0, bloco)),
    l => IO.bind(Array<U32>, Array<U32> & U32,
      ler_blocos.go(k, l, [0 : U32^M.log2_ceil(n)], bloco, 0),
      arr => IO.pure(Array<U32> & U32, (arr, n))))

def ler_blocos.tamanho(r: File & U32, +bloco: U32) -> IO(Array<U32> & U32):
  (f, +n) = r
  match n:
    case 0: ler_blocos.vazio(f)
    case _: ler_blocos.cheio(f, n, bloco)

def ler_blocos(caminho: String, +bloco: U32) -> IO(Array<U32> & U32):
  do IO<Array<U32> & U32>:
    f : File <- abrir(caminho, "r")
    r : File & U32 <- tentar(U32, File.size(f))
    ler_blocos.tamanho(r, bloco)

def bloco_padrao() -> U32: 1048576

def ler_bytes(caminho: String) -> IO(Array<U32> & U32):
  ler_blocos(caminho, bloco_padrao())

# ----------------------------------------------------------------
# BYTES: ESCRITA
# ----------------------------------------------------------------

# Grava em blocos de `bloco` bytes, um `File.write_bytes` por bloco.
# O estado do laço são dois pares: o handle devolvido pela escrita anterior e
# o bloco da vez já como lista (uma lambda não pode desestruturar o próprio
# parâmetro, então é a próxima chamada que o abre). `k` conta os que faltam.
def gravar_blocos.go(k: Nat, fu: File & Unit, r: Array<U32> & List<&2, U32>, +bloco: U32, +pos: U32, +n: U32) -> IO(Unit):
  match k:
    case 0n:
      (f, u) = fu
      (arr, xs) = r
      IO.bind(File & Unit, Unit, tentar(Unit, File.write_bytes(f, xs)), fecha)
    case 1n+p:
      (f, u) = fu
      (arr, xs) = r
      +prox = (pos + bloco : U32)
      IO.bind(File & Unit, Unit, tentar(Unit, File.write_bytes(f, xs)), fu2 =>
        gravar_blocos.go(p, fu2, array_para_lista(arr, prox, U32.min(bloco, (n - prox : U32))), bloco, prox, n))

def par_file(f: File) -> File & Unit:
  (f, Unit{})

def gravar_blocos.cheio(caminho: String, arr: Array<U32>, +n: U32, +bloco: U32) -> IO(Unit):
  +k = U32.to_nat(((n + bloco - 1 : U32) / bloco - 1 : U32))
  IO.bind(File, Unit, abrir(caminho, "w"), f =>
    gravar_blocos.go(k, par_file(f), array_para_lista(arr, 0, U32.min(bloco, n)), bloco, 0, n))

def gravar_blocos(caminho: String, arr: Array<U32>, +n: U32, +bloco: U32) -> IO(Unit):
  match n:
    # Nada a gravar: só cria (ou trunca) o arquivo
    case 0: IO.bind(File, Unit, abrir(caminho, "w"), File.close)
    case _: gravar_blocos.cheio(caminho, arr, n, bloco)

def gravar_bytes(caminho: String, arr: Array<U32>, +n: U32) -> IO(Unit):
  gravar_blocos(caminho, arr, n, bloco_padrao())
