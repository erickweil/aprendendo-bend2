import Base
import ./../utils/json.bend as J

# ==============================================================================
# TESTES DO PARSER/SERIALIZADOR JSON (genetic/utils/json.bend)
# ==============================================================================
# Este arquivo FALHA de verdade: cada checagem compara um valor observado com o
# esperado e a contagem de falhas aparece na ultima linha. A versao anterior
# imprimia "Parser com Sucesso? True" como texto literal, entao passava mesmo
# quando o serializador emitia "True"/"False" — JSON invalido que nem voltava
# pelo proprio tokenizer.
# ==============================================================================

# `match` nao pode escrutinar valor computado (AGENTS.md, Armadilha 6), entao o
# ParseRes entra como parametro destes auxiliares.
def res_is_ok(r: J.ParseRes) -> Bool:
  match r:
    case J.POk{_}: True{}
    case J.PFail{_}: False{}

def res_num(r: J.ParseRes, key: String, +default: U32) -> U32:
  match r:
    case J.POk{ast}: J.Json.get_num(ast, key, default)
    case J.PFail{_}: default

def res_str(r: J.ParseRes, key: String, default: String) -> String:
  match r:
    case J.POk{ast}: J.Json.get_str(ast, key, default)
    case J.PFail{_}: default

def res_arr_len(r: J.ParseRes, key: String) -> Nat:
  match r:
    case J.POk{ast}: List.length(&2, J.Json, J.Json.get_arr(ast, key))
    case J.PFail{_}: 0n

def res_stringify(r: J.ParseRes) -> String:
  match r:
    case J.POk{ast}: J.Json.stringify(ast)
    case J.PFail{msg}: "PARSE_FAIL: " ++ msg

def bool_of_json(m: Maybe<&2, J.Json>) -> U32:
  match m:
    case None{}: 9
    case Some{v}:
      match v:
        case J.JBool{b}: Bool.pick(U32, b, 1, 0)
        case _: 8

def res_bool_code(r: J.ParseRes, key: String) -> U32:
  match r:
    case J.POk{ast}: bool_of_json(J.Json.get(ast, key))
    case J.PFail{_}: 7

def line(ok: Bool, name: String) -> String:
  match ok:
    case True{}:  "  [OK]    " ++ name ++ "\n"
    case False{}: "  [FALHA] " ++ name ++ "\n"

def fail_count(ok: Bool) -> U32:
  Bool.pick(U32, ok, 0, 1)

def verdict(n: U32) -> String:
  Bool.pick(String, U32.is_zero(n), "TODOS OS TESTES PASSARAM\n", "HOUVE FALHAS\n")

def src() -> String:
  "{\"nome\": \"101\", \"tempos\": [1, 2, 3], \"ativo\": true, \"inativo\": false, \"vazio\": null, \"aulas\": 4}"

def main() -> IO(Unit):
  # --- parsing basico ---
  +t1 = U32.is_eq(res_num(J.parse_json(src()), "aulas", 0), 4)
  +t2 = String.eq(res_str(J.parse_json(src()), "nome", ""), "101")
  +t3 = Nat.is_eq(res_arr_len(J.parse_json(src()), "tempos"), 3n)
  +t4 = U32.is_eq(res_num(J.parse_json(src()), "inexistente", 77), 77)

  # --- booleanos (regressao: Bool.show emitia "True"/"False") ---
  +t5 = U32.is_eq(res_bool_code(J.parse_json(src()), "ativo"), 1)
  +t6 = U32.is_eq(res_bool_code(J.parse_json(src()), "inativo"), 0)
  +t7 = String.eq(J.Json.stringify(J.JBool{True{}}), "true")
  +t8 = String.eq(J.Json.stringify(J.JBool{False{}}), "false")
  +t9 = String.eq(J.Json.stringify(J.JNull{}), "null")

  # --- ida e volta: stringify tem que produzir algo que o parser aceita ---
  +round = J.parse_json(res_stringify(J.parse_json(src())))
  +t10 = res_is_ok(round)
  +t11 = U32.is_eq(res_num(J.parse_json(res_stringify(J.parse_json(src()))), "aulas", 0), 4)
  +t12 = U32.is_eq(res_bool_code(J.parse_json(res_stringify(J.parse_json(src()))), "ativo"), 1)
  +t13 = U32.is_eq(res_bool_code(J.parse_json(res_stringify(J.parse_json(src()))), "inativo"), 0)

  # --- estruturas vazias e entrada malformada ---
  +t14 = res_is_ok(J.parse_json("{}"))
  +t15 = res_is_ok(J.parse_json("[]"))
  +t16 = Bool.not(res_is_ok(J.parse_json("{\"a\": ")))
  +t17 = Bool.not(res_is_ok(J.parse_json("[1, 2")))

  +n = (fail_count(t1) + fail_count(t2) + fail_count(t3) + fail_count(t4) +
        fail_count(t5) + fail_count(t6) + fail_count(t7) + fail_count(t8) +
        fail_count(t9) + fail_count(t10) + fail_count(t11) + fail_count(t12) +
        fail_count(t13) + fail_count(t14) + fail_count(t15) + fail_count(t16) +
        fail_count(t17) : U32)

  IO.print(
    "=== TESTES DO PARSER/SERIALIZADOR JSON ===\n" ++
    line(t1,  "get_num extrai aulas = 4") ++
    line(t2,  "get_str extrai nome = \"101\"") ++
    line(t3,  "get_arr devolve 3 tempos") ++
    line(t4,  "get_num usa o default quando a chave nao existe") ++
    line(t5,  "parse preserva true") ++
    line(t6,  "parse preserva false") ++
    line(t7,  "stringify(JBool true) == \"true\" (minusculo, RFC 8259)") ++
    line(t8,  "stringify(JBool false) == \"false\"") ++
    line(t9,  "stringify(JNull) == \"null\"") ++
    line(t10, "ida e volta: stringify -> parse volta a ser POk") ++
    line(t11, "ida e volta preserva aulas = 4") ++
    line(t12, "ida e volta preserva true") ++
    line(t13, "ida e volta preserva false") ++
    line(t14, "objeto vazio {} e aceito") ++
    line(t15, "array vazio [] e aceito") ++
    line(t16, "objeto truncado e rejeitado") ++
    line(t17, "array truncado e rejeitado") ++
    "Falhas: " ++ U32.show(n) ++ "\n" ++
    verdict(n)
  )
