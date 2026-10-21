import Base
import ./../utils/io.bend as IOU
import ./../utils/random.bend as R

# ÁRVORE BINÁRIA DE BUSCA genérica: um tipo com parâmetro (`Arvore<T>`) e
# funções com TEMPLATES (`~T`, `~cmp`), que viram código especializado para
# cada tipo usado, sem custo em tempo de execução.
type Arvore<-T: Data> is Data:
  Vazia{}
  No{valor: T, esq: Arvore<T>, dir: Arvore<T>}

# DESCER POR UM LADO SÓ. O jeito óbvio de inserir é ERRADO em Bend:
#
#   Bool.pick(Arvore<T>, Cmp.is_lt(cmp(novo, v)),
#     No{v, inserir(esq, novo), dir},
#     No{v, esq, inserir(dir, novo)})
#
# `Bool.pick` calcula os DOIS lados: a inserção desce pela árvore INTEIRA,
# O(n) em vez de O(log n). Medido no nativo: 4000 inserções em 777 ms com o
# `pick`, 4 ms com o padrão abaixo (e 1 milhão em ~2 s). E o `match` sobre a comparação não pode chamar
# `inserir` de volta (não há recursão mútua). A saída: quem desce já leva a
# comparação com a raiz do filho como PARÂMETRO (`lado`), e o `match` escolhe
# o caminho. `lado_de` é o auxiliar não recursivo que calcula essa comparação.
def lado_de(~T: Data, ~cmp: T -> T -> Cmp, +a: Arvore<T>, +x: T) -> Cmp:
  match a:
    case Vazia{}: EQ{}
    case No{v, e, d}: cmp(x, v)

def inserir.go(~T: Data, ~cmp: T -> T -> Cmp, a: Arvore<T>, lado: Cmp, +novo: T) -> Arvore<T>:
  match a lado:
    case Vazia{} _:
      No{novo, Vazia{}, Vazia{}}
    case No{v, +e, d} LT{}:
      No{v, inserir.go(~T, ~cmp, e, lado_de(~T, ~cmp, e, novo), novo), d}
    case No{v, e, d} EQ{}:
      No{v, e, d}                                   # já existe
    case No{v, e, +d} GT{}:
      No{v, e, inserir.go(~T, ~cmp, d, lado_de(~T, ~cmp, d, novo), novo)}

def inserir(~T: Data, ~cmp: T -> T -> Cmp, +a: Arvore<T>, +novo: T) -> Arvore<T>:
  inserir.go(~T, ~cmp, a, lado_de(~T, ~cmp, a, novo), novo)

# Buscar segue o mesmo padrão
def contem.go(~T: Data, ~cmp: T -> T -> Cmp, a: Arvore<T>, lado: Cmp, +x: T) -> Bool:
  match a lado:
    case Vazia{} _: False{}
    case No{v, e, d} EQ{}: True{}
    case No{v, +e, d} LT{}: contem.go(~T, ~cmp, e, lado_de(~T, ~cmp, e, x), x)
    case No{v, e, +d} GT{}: contem.go(~T, ~cmp, d, lado_de(~T, ~cmp, d, x), x)

def contem(~T: Data, ~cmp: T -> T -> Cmp, +a: Arvore<T>, +x: T) -> Bool:
  contem.go(~T, ~cmp, a, lado_de(~T, ~cmp, a, x), x)

# Percurso em ordem, dobrando `f` sobre os valores
def em_ordem(~T: Data, ~S: Data, ~f: S -> T -> S, a: Arvore<T>, acc: S) -> S:
  match a:
    case Vazia{}: acc
    case No{v, e, d}: em_ordem(~T, ~S, ~f, d, f(em_ordem(~T, ~S, ~f, e, acc), v))

# Os dois lados são independentes: dá para medir em paralelo
def altura(~T: Data, a: Arvore<T>) -> U32:
  match a:
    case Vazia{}: 0
    case No{v, e, d}:
      he hd = altura(~T, e) altura(~T, d)
      (1 + U32.max(he, hd) : U32)

def tamanho(~T: Data, a: Arvore<T>) -> U32:
  match a:
    case Vazia{}: 0
    case No{v, e, d}:
      te td = tamanho(~T, e) tamanho(~T, d)
      (1 + te + td : U32)

# --- usando com U32 ---

def de_lista(xs: List<&2, U32>, +a: Arvore<U32>) -> Arvore<U32>:
  match xs:
    case Nil{}: a
    case h <> t: de_lista(t, inserir(~U32, ~U32.cmp, a, h))

def mostra(s: String, x: U32) -> String:
  s ++ " " ++ U32.show(x)

# Um `match`, não um `Bool.pick`: o pick montaria o texto da árvore inteira
# mesmo quando ele não vai ser mostrado (e com `++` à esquerda isso é O(n²):
# 10 mil valores levavam 1,8 s; 20 mil, 8 s).
def listar(pequena: Bool, a: Arvore<U32>) -> String:
  match pequena:
    case True{}: "em ordem:" ++ em_ordem(~U32, ~String, ~mostra, a, "")
    case False{}: "(árvore grande: não mostrada)"

# Uso: arvore [n=10] [semente=0: aleatória] [busca=7]
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +n : U32 = IOU.num_at(ns, 0n, 10)
    +s : U32 <- IOU.semente(IOU.num_at(ns, 1n, 0))
    +x : U32 = IOU.num_at(ns, 2n, 7)
    t0 : Nat <- IO.now()
    +a : Arvore<U32> = de_lista(R.list(U32.to_nat(n), s, (n * 4 : U32)), Vazia{})
    IO.print(U32.show(n) ++ " sorteios em [0, " ++ U32.show((n * 4 : U32)) ++ "): " ++
      U32.show(tamanho(~U32, a)) ++ " valores distintos, altura " ++ U32.show(altura(~U32, a)))
    dt : String <- IOU.tempo_desde(t0)
    IO.print("  (montada em " ++ dt ++ ")")
    IO.print("contém " ++ U32.show(x) ++ "? " ++ Bool.show(contem(~U32, ~U32.cmp, a, x)))
    IO.print(listar((n <= 30 : U32), a))
