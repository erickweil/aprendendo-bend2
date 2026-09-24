import Base
import ./../utils/io.bend as IOU

# UM SERVIDOR HTTP MÍNIMO com TCP: aceita `n` conexões, responde uma página
# de texto a cada uma e encerra.
#
#   bend servidor.bend -o ../bin/servidor
#   ../bin/servidor [porta=8080] [conexões=3]
#   curl http://localhost:8080/        (em outro terminal)
#
# Um `Socket` (ou `Listener`) é um handle AFIM: todo efeito sobre ele o
# devolve junto com o resultado, num par `Socket & Result<.., A>`, e é por
# esse handle devolvido que se continua. Como só se desestrutura parâmetro,
# cada passo é uma def que recebe o par da ação anterior.
#
# O laço de conexões tem combustível (`Nat`): todo laço termina em Bend. Um
# servidor "infinito" usa um combustível enorme, como o `App.run` da Base.

def Erro() -> Type:
  U32 & String

# Sem `Content-Length`: com `Connection: close`, o fim da conexão marca o
# fim do corpo (e `String.length` contaria caracteres, não os bytes UTF-8)
def resposta(+i: U32, pedido: String) -> String:
  "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n" ++
    "Olá do Bend! Você é a visita " ++ U32.show(i) ++ ".\n" ++
    "Primeira linha do seu pedido: " ++ Maybe.default(&2, String, List.head(&2, String, String.lines(pedido)), "") ++ "\n"

def fecha(par: Socket & Result<&1, &1, Erro(), Unit>) -> IO(Unit):
  (s, r) = par
  Socket.close(s)

def responde(par: Socket & Result<&1, &1, Erro(), String>, +i: U32) -> IO(Unit):
  (s, r) = par
  match r:
    case Fail{e}:
      Socket.close(s)
    case Done{pedido}:
      do IO<Unit>:
        IO.print("visita " ++ U32.show(i))
        enviado : Socket & Result<&1, &1, Erro(), Unit> <- TCP.send(s, resposta(i, pedido))
        fecha(enviado)

def atende(r: Result<&1, &1, Erro(), Socket>, +i: U32) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print_err("falha ao aceitar")
    case Done{s}:
      do IO<Unit>:
        pedido : Socket & Result<&1, &1, Erro(), String> <- TCP.recv(s, 4096)
        responde(pedido, i)

# `aceito` é o par devolvido pelo `TCP.accept` anterior
def servir(k: Nat, aceito: Listener & Result<&1, &1, Erro(), Socket>, +i: U32) -> IO(Unit):
  match k:
    case 0n:
      (l, r) = aceito
      do IO<Unit>:
        atende(r, i)
        Listener.close(l)
    case 1n+p:
      (l, r) = aceito
      do IO<Unit>:
        atende(r, i)
        prox : Listener & Result<&1, &1, Erro(), Socket> <- TCP.accept(l)
        servir(p, prox, (i + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +porta : U32 = IOU.num_at(ns, 0n, 8080)
    +n : U32 = U32.max(IOU.num_at(ns, 1n, 3), 1)
    l : Listener <- IO.try(Listener, TCP.listen(porta))
    IO.print("ouvindo em http://localhost:" ++ U32.show(porta) ++ "/ (" ++ U32.show(n) ++ " conexões)")
    primeiro : Listener & Result<&1, &1, Erro(), Socket> <- TCP.accept(l)
    servir(U32.to_nat((n - 1 : U32)), primeiro, 1)
    IO.print("fim")
