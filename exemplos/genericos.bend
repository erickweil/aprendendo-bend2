import Base

# GENÉRICOS: tipos e funções com parâmetros de tipo.
#
#   -A: Data      um tipo APAGADO: só o verificador o vê; uma única versão
#                 compilada serve para todos os tipos.
#   ~A: Data      um tipo TEMPLATE: cada tipo usado gera sua própria versão
#                 (especializada, como os genéricos do Rust).
#   a, -A: Kind(a)  genérico também na QUANTIDADE: serve para tipos que
#                 podem (`Data` = Kind(&2)) ou não (`Type` = Kind(&1)) ser
#                 duplicados.

# Um tipo com dois parâmetros
type Par<-A: Data, -B: Data> is Data:
  Par{fst: A, snd: B}

def Par.troca(-A: Data, -B: Data, p: Par<A, B>) -> Par<B, A>:
  match p:
    case Par{a, b}: Par{b, a}

# Uma pilha genérica
type Pilha<-A: Data> is Data:
  Pilha{itens: List<&2, A>, tamanho: U32}

def Pilha.nova(-A: Data) -> Pilha<A>:
  Pilha{[], 0}

def Pilha.push(-A: Data, p: Pilha<A>, x: A) -> Pilha<A>:
  match p:
    case Pilha{itens, n}: Pilha{x <> itens, (n + 1 : U32)}

def Pilha.topo(-A: Data, p: Pilha<A>) -> Maybe<&2, A>:
  match p:
    case Pilha{itens, n}: List.head(&2, A, itens)

def Par.show(p: Par<String, U32>) -> String:
  match p:
    case Par{s, n}: s ++ ", " ++ U32.show(n)

def aspas(s: String) -> String:
  "\"" ++ s ++ "\""

def Pilha.tamanho(-A: Data, p: Pilha<A>) -> U32:
  match p:
    case Pilha{itens, n}: n

# Genérico na quantidade: conta os elementos de QUALQUER lista, inclusive de
# uma lista de funções (que são `Type` e não podem ser duplicadas)
def conta(a, -A: Kind(a), xs: List<a, A>) -> U32:
  match xs:
    case Nil{}: 0
    case h <> t: (1 + conta(a, A, t) : U32)

def dobra(x: U32) -> U32:
  (2 * x : U32)

# TEMPLATE obrigatório: um laço recursivo sobre `Array<T>` com `-T: Data`
# passa no verificador mas NÃO compila para nativo ("an open Array element
# type"): o backend precisa saber o tipo do elemento. Com `~T` cada uso
# gera uma cópia com o tipo concreto. `~mais` também é template (colado no
# lugar, sem custo de chamada) — e os templates vêm antes de tudo na
# assinatura, então um tipo citado por um template tem de ser template.
def soma.go(~T: Data, ~mais: T -> T -> T, k: Nat, r: Array<T> & T, +i: U32, acc: T) -> T:
  match k:
    case 0n:
      (a, v) = r
      mais(acc, v)
    case 1n+p:
      (a, v) = r
      soma.go(~T, ~mais, p, Array.get(T, a, (i + 1 : U32)), (i + 1 : U32), mais(acc, v))

def soma(~T: Data, ~mais: T -> T -> T, a: Array<T>, zero: T) -> T:
  soma.go(~T, ~mais, 7n, Array.get(T, a, 0), 0, zero)

def mais_u32(a: U32, b: U32) -> U32:
  (a + b : U32)

def mais_f32(a: F32, b: F32) -> F32:
  (a + b : F32)

def main() -> IO(Unit):
  p = Par.troca(U32, String, Par{7, "sete"})
  pilha = Pilha.push(String, Pilha.push(String, Pilha.nova(String), "a"), "b")
  +pilha = Pilha.push(String, pilha, "c")
  funcoes : List<&1, U32 -> U32> = [dobra, U32.inc, (+x => (x * x : U32))]
  do IO<Unit>:
    IO.print("Par trocado: " ++ Par.show(p))
    IO.print("Pilha: topo " ++ Maybe.show(~&2, ~String, ~aspas, Pilha.topo(String, pilha)) ++
      ", tamanho " ++ U32.show(Pilha.tamanho(String, pilha)))
    IO.print("conta de U32: " ++ U32.show(conta(&2, U32, [1, 2, 3, 4])) ++
      ", conta de funções: " ++ U32.show(conta(&1, U32 -> U32, funcoes)))
    IO.print("soma de 8 U32: " ++ U32.show(soma(~U32, ~mais_u32, [5 : U32*8n], 0)) ++
      ", soma de 8 F32: " ++ F32.show(soma(~F32, ~mais_f32, Array.new(F32, 3n, 0.5), 0.0)))
