import Base
import ./../utils/io.bend as IOU
import ./../utils/random.bend as R
import ./../utils/arrays.bend as Arr

# HISTOGRAMA PARALELO: sorteia números em [0, 16) em várias tarefas e conta
# quantos caíram em cada faixa. Duas formas:
#
# A) COMPARTILHADO: um array só, dividido entre as tarefas com `Array.fork`
#    (dois handles para o MESMO bloco), e cada contagem com
#    `Array.atomic.add`, que soma certo mesmo quando duas tarefas batem no
#    mesmo slot. `Array.fork`/`Array.join` são `@unsafe` na Base (nada
#    garante que as escritas não se cruzem): o `--check-only` lista as defs
#    que dependem deles.
#
# B) LOCAL: cada tarefa conta no SEU array, e os arrays são somados na volta
#    das chamadas paralelas. Nada é compartilhado.
#
# As duas dão exatamente o mesmo histograma (as tarefas usam os mesmos
# fluxos de sorteio). Medido no nativo, 64 milhões de sorteios:
#
#   threads    A) compartilhado    B) local
#      1           342 ms           172 ms
#      4          1361 ms            61 ms
#     12          1349 ms            38 ms
#
# Com 16 faixas, todas as tarefas disputam as mesmas 16 posições: o atômico
# CONTESTADO faz o programa ficar 4× mais LENTO com mais threads. O atômico
# serve para o ponto de encontro raro (um contador, um acumulador), não para
# o laço quente; no laço quente, cada tarefa com o seu rascunho.

def descarta(r: Array<U32> & U32) -> Array<U32>:
  (a, velho) = r
  a

# ----------------------------------------------------------------
# A) um array compartilhado, com atômicos
# ----------------------------------------------------------------
def conta.atomico(k: Nat, h: Array<U32>, +s: U32) -> Array<U32>:
  match k:
    case 0n: h
    case 1n+p: conta.atomico(p, descarta(Array.atomic.add(h, R.range(s, 16), 1)), R.step(s))

# Recebe os DOIS handles de um fork como parâmetro (um par só se abre como
# parâmetro), entrega um a cada lado da chamada paralela e junta de volta.
def compartilhado(prof: Nat, hs: Array<U32> & Array<U32>, +s: U32, +n: Nat) -> Array<U32>:
  match prof:
    case 0n:
      (a, b) = hs
      x y = conta.atomico(n, a, R.split.fst(s)) conta.atomico(n, b, R.split.snd(s))
      Array.join(U32, x, y)
    case 1n+ +p:
      (a, b) = hs
      x y =
        compartilhado(p, Array.fork(U32, a), R.split.fst(s), n)
        compartilhado(p, Array.fork(U32, b), R.split.snd(s), n)
      Array.join(U32, x, y)

# ----------------------------------------------------------------
# B) um array por tarefa, somados na volta
# ----------------------------------------------------------------
def conta.local(k: Nat, h: Array<U32>, +s: U32) -> Array<U32>:
  match k:
    case 0n: h
    case 1n+p:
      conta.local(p, Arr.modify(~U32, ~U32.inc, h, R.range(s, 16)), R.step(s))

def soma(a: U32, b: U32, i: U32) -> U32:
  (a + b : U32)

def local(prof: Nat, +s: U32, +n: Nat) -> Array<U32>:
  match prof:
    case 0n:
      conta.local(n, [0 : U32*16n], s)
    case 1n+ +p:
      x y = local(p, R.split.fst(s), n) local(p, R.split.snd(s), n)
      Arr.zip_with(~U32, ~U32, ~soma, x, y)

def mostra(a: Array<U32>) -> String:
  Arr.show(~U32, ~U32.show, a)

# Uso: histograma [milhões de sorteios=16] [semente=0: aleatória]
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +milhoes : U32 = U32.max(IOU.num_at(ns, 0n, 16), 1)
    +s : U32 <- IOU.semente(IOU.num_at(ns, 1n, 0))
    # 64 tarefas; cada uma sorteia (milhões / 64) milhões
    +n : Nat = U32.to_nat((milhoes * 16384 : U32))
    +t0 : Nat <- IO.now()
    IO.print("A) compartilhado: " ++ mostra(compartilhado(5n, Array.fork(U32, [0 : U32*16n]), s, n)))
    dt0 : String <- IOU.tempo_desde(t0)
    IO.print("   " ++ dt0)
    +t1 : Nat <- IO.now()
    IO.print("B) local:         " ++ mostra(local(6n, s, n)))
    dt1 : String <- IOU.tempo_desde(t1)
    IO.print("   " ++ dt1)
