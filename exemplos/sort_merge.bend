import Base
import ./../utils/io.bend as IOU
import ./../utils/random.bend as R
import ./../utils/math.bend as M

# MERGE SORT PARALELO: divide a lista em duas metades, ordena as duas AO
# MESMO TEMPO (`x y = f(a) g(b)`, a chamada paralela) e junta.
#
# Duas lições medidas no nativo (1 milhão de números, i5-1245U):
#
# 1. GRANULARIDADE. Dividir até sobrar um elemento cria um milhão de tarefas
#    minúsculas. Aqui só os 5 níveis de cima são paralelos (32 tarefas), e
#    cada folha ordena o seu pedaço com o `List.sort` da Base.
#
# 2. LOCALIDADE. Uma lista é uma cadeia de células espalhadas pelo heap, e
#    percorrê-la fora da cache custa caro. Dividir ALTERNANDO os elementos
#    ([a,c,e] e [b,d]) entrelaça as células das duas metades: numa medição
#    isolada (gerar e ordenar), 2,4 s. Dividir em prefixo e sufixo mantém
#    cada metade junta: 0,96 s, contra 1,5 s do `List.sort` sozinho.
#
# Na bateria, este programa leva 2,2 s com 1 thread, 1,9 s com 2 e 1,7 s
# com 4 ou 8; mais threads não ajudam: com listas encadeadas o limite passa a
# ser a memória, não a CPU. Compare com `pow.bend`, que não toca na memória e
# escala 4×.

# Separa os k primeiros elementos: ([k primeiros], resto). A recursão devolve
# um PAR, e quem o abre é um auxiliar não recursivo que o recebe como
# parâmetro (só se desestrutura parâmetro, nunca o retorno de uma chamada).
def partir.poe(h: U32, r: List<&2, U32> & List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  (a, b) = r
  (h <> a, b)

def partir(k: Nat, l: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match k l:
    case 0n resto: ([], resto)
    case _ Nil{}: ([], [])
    case 1n+p h <> t: partir.poe(h, partir(p, t))

def em_ordem(a: U32, b: U32) -> Bool:
  (a <= b : U32)

# Junta duas listas ordenadas (`List.merge.go` da Base; `n` limita os passos)
def juntar(+n: Nat, a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  List.merge.go(~U32, ~em_ordem, n, (Nil{}, a, b))

# Recebe as duas metades já separadas (com os tamanhos), ordena cada uma e
# junta. `prof` diz quantos níveis ainda dividem em paralelo.
def ordenar(prof: Nat, metades: List<&2, U32> & List<&2, U32>, +na: U32, +nb: U32, +n: Nat) -> List<&2, U32>:
  match prof:
    case 0n:
      (a, b) = metades
      x y = List.sort(~U32, ~em_ordem, a) List.sort(~U32, ~em_ordem, b)
      juntar(n, x, y)
    case 1n+ +p:
      (a, b) = metades
      +ha = (na / 2 : U32)
      +hb = (nb / 2 : U32)
      x y =
        ordenar(p, partir(U32.to_nat(ha), a), ha, (na - ha : U32), n)
        ordenar(p, partir(U32.to_nat(hb), b), hb, (nb - hb : U32), n)
      juntar(n, x, y)

def merge_sort(+l: List<&2, U32>) -> List<&2, U32>:
  +n = List.length(&2, U32, l)
  +len = U32.from_nat(n)
  +h = (len / 2 : U32)
  ordenar(Nat.min(5n, M.log2_ceil(len)), partir(U32.to_nat(h), l), h, (len - h : U32), n)

def ordenada(+l: List<&2, U32>) -> Bool:
  match l:
    case a <> +b <> t: (a <= b : U32) && ordenada(b <> t)
    case _: True{}

# Um `match`, não um `Bool.pick`: o pick montaria o texto da lista inteira
# mesmo quando ele não vai ser mostrado (AGENTS.md, Armadilha 2)
def mostrar.se(pequena: Bool, l: List<&2, U32>) -> String:
  match pequena:
    case True{}: List.show(~&2, ~U32, ~U32.show, l)
    case False{}: "(lista grande: não mostrada)"

def mostrar(+l: List<&2, U32>) -> String:
  mostrar.se(Nat.is_le(List.length(&2, U32, l), 20n), l)

# Uso: sort_merge [n=12] [semente=0: aleatória]
#   bend sort_merge.bend -o ../bin/sort_merge
#   ../bin/sort_merge 1000000 7 --threads 1     (compare com --threads 2, 4)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +n : U32 = IOU.num_at(ns, 0n, 12)
    +s : U32 <- IOU.semente(IOU.num_at(ns, 1n, 0))
    # duas cópias: uma para mostrar e uma só do merge_sort (uma lista `+`
    # compartilhada pagaria contagem de referência a cada célula)
    lista : List<&2, U32> = R.list(U32.to_nat(n), s, 1000000)
    IO.print("original: " ++ mostrar(R.list(U32.to_nat(n), s, 1000000)))
    t0 : Nat <- IO.now()
    +ord : List<&2, U32> = merge_sort(lista)
    IO.print("ordenada: " ++ mostrar(ord) ++ " (em ordem? " ++ Bool.show(ordenada(ord)) ++ ")")
    dt : String <- IOU.tempo_desde(t0)
    IO.print(U32.show(n) ++ " números em " ++ dt)
