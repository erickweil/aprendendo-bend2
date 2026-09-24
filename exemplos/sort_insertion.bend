import Base
import ./../utils/io.bend as IOU
import ./../utils/random.bend as R

# INSERTION SORT, e como parar uma recursão no meio.
#
# Inserir x numa lista ordenada é: se x <= cabeça, x vai na frente; senão a
# cabeça fica e x é inserido no resto. O jeito óbvio é ERRADO em Bend:
#
#   Bool.pick(List<&2, U32>, (x <= h : U32), x <> h <> t, h <> inserir(x, t))
#
# `Bool.pick` é estrito: calcula os DOIS lados, então a recursão desce até o
# fim da lista mesmo quando x já achou o lugar. E a condição não pode ir num
# `match` (ele só olha parâmetros), nem num auxiliar que chame `inserir` de
# volta (não existe recursão mútua).
#
# A saída (AGENTS.md, Armadilha 2): a condição vira PARÂMETRO da própria
# recursão. `inserir.go` recebe a cabeça atual `h` já separada e `antes`, que
# diz se x vai antes dela. O caso `True{}` devolve sem mencionar a recursão.
#
# Medido no nativo (números aleatórios): 8000 números em 0,12 s, contra
# 2,49 s da versão com `Bool.pick` (20×; os dois são O(n²), mas o `pick`
# reconstrói a lista inteira a cada inserção).
def inserir.go(t: List<&2, U32>, antes: Bool, +h: U32, +x: U32) -> List<&2, U32>:
  match t antes:
    case resto True{}: x <> h <> resto
    case Nil{} False{}: h <> [x]
    case +h2 <> t2 False{}: h <> inserir.go(t2, (x <= h2 : U32), h2, x)

def inserir(+x: U32, l: List<&2, U32>) -> List<&2, U32>:
  match l:
    case Nil{}: [x]
    case +h <> t: inserir.go(t, (x <= h : U32), h, x)

def ordenar(l: List<&2, U32>) -> List<&2, U32>:
  match l:
    case Nil{}: Nil{}
    case h <> t: inserir(h, ordenar(t))

def ordenada(+l: List<&2, U32>) -> Bool:
  match l:
    case a <> +b <> t: (a <= b : U32) && ordenada(b <> t)
    case _: True{}

def mostrar(+l: List<&2, U32>) -> String:
  Bool.pick(String, Nat.is_le(List.length(&2, U32, l), 20n),
    List.show(~&2, ~U32, ~U32.show, l), "(lista grande: não mostrada)")

# Uso: sort_insertion [n=12] [semente=0: aleatória]
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +n : U32 = IOU.num_at(ns, 0n, 12)
    s : U32 <- IOU.semente(IOU.num_at(ns, 1n, 0))
    +lista : List<&2, U32> = R.list(U32.to_nat(n), s, 1000)
    IO.print("original: " ++ mostrar(lista))
    t0 : Nat <- IO.now()
    +ord : List<&2, U32> = ordenar(lista)
    IO.print("ordenada: " ++ mostrar(ord) ++ " (em ordem? " ++ Bool.show(ordenada(ord)) ++ ")")
    dt : String <- IOU.tempo_desde(t0)
    IO.print(U32.show(n) ++ " números em " ++ dt)
