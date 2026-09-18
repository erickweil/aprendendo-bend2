import Base
import ./../utils/json.bend as J

def test_json_str() -> String:
  "{\"turmas\": [{\"nome\": \"101\", \"tempos\": [1, 2, 3]}], \"ativo\": true, \"vazio\": null, \"aulas\": 4}"

def test_runner(res: J.ParseRes) -> IO(Unit):
  match res:
    case J.POk{+ast}:
      +ativo = J.Json.get(ast, "ativo")
      +aulas = J.Json.get_num(ast, "aulas", 0)
      +serialized = J.Json.stringify(ast)
      IO.print(
        "=== TESTE DO PARSER JSON EM BEND 2 ===\n" ++
        "Aulas Extraidas: " ++ U32.show(aulas) ++ "\n" ++
        "Serializado:     " ++ serialized ++ "\n" ++
        "Parser com Sucesso? True\n"
      )
    case J.PFail{err}:
      IO.print("Erro ao parsear JSON: " ++ err ++ "\n")

def main() -> IO(Unit):
  test_runner(J.parse_json(test_json_str()))
