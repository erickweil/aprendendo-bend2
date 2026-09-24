import Base
import ./../utils/io.bend as IOU

# CONCORRÊNCIA: várias computações de IO intercaladas por um laço de eventos
# (como no Node.js). Uma que espera (um sleep, um canal, um socket) sai da
# frente e deixa as outras andarem.
#
#   IO.fork(A, acao)   -> IO(Chan(A))   começa `acao` e devolve o canal por
#                                        onde o resultado vai chegar
#   IO.join(A, canal)  -> IO(A)         espera o resultado
#   Chan.new(A, n)                      um canal com espaço para n valores
#   Chan.send / Chan.recv / Chan.close  por baixo do fork/join
#   IO.spawn(A, acao)                   começa `acao` e esquece o resultado
#
# (Isto é concorrência de IO. Paralelismo de CÁLCULO puro é a chamada
# paralela `a b = f(x) g(y)`; veja pow.bend.)

# ----------------------------------------------------------------
# 1. Duas esperas ao mesmo tempo: o total é a maior, não a soma
# ----------------------------------------------------------------
def tarefa(nome: String, +ms: U32) -> IO(String):
  do IO<String>:
    IO.sleep(ms)
    return nome ++ " terminou depois de " ++ U32.show(ms) ++ " ms"

# ----------------------------------------------------------------
# 2. Produtor e consumidor ligados por um canal
# ----------------------------------------------------------------
# O produtor manda i, i+1, ... (k valores) e fecha o canal
def produz(k: Nat, +c: Chan(U32), +i: U32) -> IO(Unit):
  match k:
    case 0n:
      Chan.close(U32, c)
    case 1n+p:
      do IO<Unit>:
        ok : Bool <- Chan.send(U32, c, i)
        produz(p, c, (i + 1 : U32))

# O consumidor soma o que chega até o canal fechar (`None`). O valor
# recebido é PARÂMETRO do laço, para ser aberto pelo `match` (e o `Nat`
# limita as voltas, como todo laço).
def consome(k: Nat, recebido: Maybe<&1, U32>, +c: Chan(U32), +soma: U32) -> IO(U32):
  match k recebido:
    case _ None{}:
      IO.pure(U32, soma)
    case 0n Some{v}:
      IO.pure(U32, (soma + v : U32))
    case 1n+p Some{v}:
      do IO<U32>:
        prox : Maybe<&1, U32> <- Chan.recv(U32, c)
        consome(p, prox, c, (soma + v : U32))

# Uso: concorrencia [n=100]
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOU.num_at(IOU.numbers(args), 0n, 100)

    +t0 : Nat <- IO.now()
    a : Chan(String) <- IO.fork(String, tarefa("A", 300))
    b : Chan(String) <- IO.fork(String, tarefa("B", 200))
    IO.print("duas tarefas começaram; esperando...")
    ra : String <- IO.join(String, a)
    rb : String <- IO.join(String, b)
    IO.print("  " ++ ra)
    IO.print("  " ++ rb)
    dt : String <- IOU.tempo_desde(t0)
    IO.print("  total: " ++ dt ++ " (e não 500 ms)")

    +c : Chan(U32) <- Chan.new(U32, 8)
    IO.spawn(Unit, produz(U32.to_nat(n), c, 1))
    primeiro : Maybe<&1, U32> <- Chan.recv(U32, c)
    soma : U32 <- consome(U32.to_nat(n), primeiro, c, 0)
    IO.print("consumidor somou 1 + ... + " ++ U32.show(n) ++ " = " ++ U32.show(soma))
