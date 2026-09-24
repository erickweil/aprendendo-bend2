import Base
import ./../utils/io.bend as IOU
import ./../utils/json.bend as J

# JSON com utils/json.bend: ler texto para uma árvore `Json`, consultar
# campos e escrever de volta.
#
#   J.parse_json(texto)                -> J.ParseRes   (POk{json} ou PFail{msg})
#   J.Json.get(json, "chave")          -> Maybe<&2, J.Json>
#   J.Json.get_str / get_num / get_arr (com valor padrão)
#   J.Json.stringify(json)             -> String
#
# Limitações: números só inteiros sem sinal (U32) e strings sem escapes.

def padrao() -> String:
  "{\"nome\": \"Bend\", \"versao\": 2, \"paralelo\": true, \"alvos\": [\"cpu\", \"gpu\", \"js\"], \"extra\": null}"

def texto(j: J.Json) -> String:
  match j:
    case J.JStr{s}: s
    case outro: J.Json.stringify(outro)

def mostra(r: J.ParseRes) -> IO(Unit):
  match r:
    case J.PFail{msg}:
      IO.print("erro: " ++ msg)
    case J.POk{+json}:
      do IO<Unit>:
        IO.print("nome:     " ++ J.Json.get_str(json, "nome", "(sem nome)"))
        IO.print("versao:   " ++ U32.show(J.Json.get_num(json, "versao", 0)))
        IO.print("alvos:    " ++ List.show(~&2, ~J.Json, ~texto, J.Json.get_arr(json, "alvos")))
        IO.print("paralelo: " ++ Maybe.show(~&2, ~J.Json, ~J.Json.stringify, J.Json.get(json, "paralelo")))
        IO.print("de volta: " ++ J.Json.stringify(json))

# Uso: json ['{"a": [1, 2]}']
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    +entrada : String = IOU.text_at(ts, 0n, padrao())
    IO.print("entrada:  " ++ entrada)
    mostra(J.parse_json(entrada))
