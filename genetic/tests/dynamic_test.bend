import Base
import ./../utils/json.bend as J
import ./../src/horario_solver.bend as H

# ==============================================================================
# TESTES DA CARGA DINAMICA E DA VALIDACAO DE ENTRADA (horario_solver.bend)
# ==============================================================================
# Este arquivo IMPORTA horario_solver.bend. A versao anterior tinha ~190 linhas
# copiadas do solver (com um repeat_val que ja divergia do original), entao
# testava uma copia, nao o codigo em producao — e imprimia
# "STATUS: CARGA DINAMICA 100% BEM-SUCEDIDA!" incondicionalmente.
#
# E hermetico: usa o fixture embutido abaixo, sem depender de HORARIO_JSON nem
# do dataset real. 3 turmas x 20 aulas, 15 disciplinas, 5 professores.
# P0 fica indisponivel em seg/tempo 1, logo sua mascara deve ser exatamente 1.
# ==============================================================================

def fixture() -> String:
  "{\"formData\":{\"turmas\":[{\"nome\":\"T-A\",\"horarios\":{\"seg\":[1,2,3,4],\"ter\":[1,2,3,4],\"qua\":[1,2,3,4],\"qui\":[1,2,3,4],\"sex\":[1,2,3,4]}},{\"nome\":\"T-B\",\"horarios\":{\"seg\":[1,2,3,4],\"ter\":[1,2,3,4],\"qua\":[1,2,3,4],\"qui\":[1,2,3,4],\"sex\":[1,2,3,4]}},{\"nome\":\"T-C\",\"horarios\":{\"seg\":[1,2,3,4],\"ter\":[1,2,3,4],\"qua\":[1,2,3,4],\"qui\":[1,2,3,4],\"sex\":[1,2,3,4]}}],\"disciplinas\":[{\"nome\":\"T-A-D0\",\"turma\":\"T-A\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-A-D1\",\"turma\":\"T-A\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-A-D2\",\"turma\":\"T-A\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-A-D3\",\"turma\":\"T-A\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-A-D4\",\"turma\":\"T-A\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-B-D0\",\"turma\":\"T-B\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-B-D1\",\"turma\":\"T-B\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-B-D2\",\"turma\":\"T-B\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-B-D3\",\"turma\":\"T-B\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-B-D4\",\"turma\":\"T-B\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-C-D0\",\"turma\":\"T-C\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-C-D1\",\"turma\":\"T-C\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-C-D2\",\"turma\":\"T-C\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-C-D3\",\"turma\":\"T-C\",\"aulas\":4,\"agrupar\":2,\"dividir\":false},{\"nome\":\"T-C-D4\",\"turma\":\"T-C\",\"aulas\":4,\"agrupar\":2,\"dividir\":false}],\"disciplinas_unidas\":[],\"professores\":[{\"nome\":\"P0\",\"disciplinas\":[\"T-A-D0\",\"T-A-D1\",\"T-A-D2\"],\"horarios\":{\"seg\":[2,3,4],\"ter\":[1,2,3,4],\"qua\":[1,2,3,4],\"qui\":[1,2,3,4],\"sex\":[1,2,3,4]}},{\"nome\":\"P1\",\"disciplinas\":[\"T-A-D3\",\"T-A-D4\",\"T-B-D0\"],\"horarios\":{\"seg\":[1,2,3,4],\"ter\":[1,2,3,4],\"qua\":[1,2,3,4],\"qui\":[1,2,3,4],\"sex\":[1,2,3,4]}},{\"nome\":\"P2\",\"disciplinas\":[\"T-B-D1\",\"T-B-D2\",\"T-B-D3\"],\"horarios\":{\"seg\":[1,2,3,4],\"ter\":[1,2,3,4],\"qua\":[1,2,3,4],\"qui\":[1,2,3,4],\"sex\":[1,2,3,4]}},{\"nome\":\"P3\",\"disciplinas\":[\"T-B-D4\",\"T-C-D0\",\"T-C-D1\"],\"horarios\":{\"seg\":[1,2,3,4],\"ter\":[1,2,3,4],\"qua\":[1,2,3,4],\"qui\":[1,2,3,4],\"sex\":[1,2,3,4]}},{\"nome\":\"P4\",\"disciplinas\":[\"T-C-D2\",\"T-C-D3\",\"T-C-D4\"],\"horarios\":{\"seg\":[1,2,3,4],\"ter\":[1,2,3,4],\"qua\":[1,2,3,4],\"qui\":[1,2,3,4],\"sex\":[1,2,3,4]}}]}}"

def line(ok: Bool, name: String) -> String:
  match ok:
    case True{}:  "  [OK]    " ++ name ++ "\n"
    case False{}: "  [FALHA] " ++ name ++ "\n"

def fail_count(ok: Bool) -> U32:
  Bool.pick(U32, ok, 0, 1)

def verdict(n: U32) -> String:
  Bool.pick(String, U32.is_zero(n), "TODOS OS TESTES PASSARAM\n", "HOUVE FALHAS\n")

def mask_at.step(m: Maybe<&2, U32>, +default: U32) -> U32:
  match m:
    case None{}: default
    case Some{v}: v

def mask_at(l: List<&2, U32>, +idx: U32, +default: U32) -> U32:
  mask_at.step(List.get(&2, U32, l, U32.to_nat(idx)), default)

def all_positive(l: List<&2, U32>) -> Bool:
  match l:
    case Nil{}: True{}
    case h <> t:
      Bool.pick(Bool, U32.is_gt(h, 0), all_positive(t), False{})

def mk_disc(nome: String, turma: String, aulas: U32) -> H.DiscEntry:
  H.DEntry{nome, turma, aulas, 2}

def run_checks.fd(+fd: J.Json) -> String:
  +turmas_arr = J.Json.get_arr(fd, "turmas")
  +discs_arr  = J.Json.get_arr(fd, "disciplinas")
  +profs_arr  = J.Json.get_arr(fd, "professores")

  +turmas     = H.load_turmas_names(turmas_arr)
  +discs      = H.load_disciplinas(discs_arr)
  +disc_profs = H.build_disc_profs(discs, profs_arr)
  +masks      = H.load_profs_unavail_masks(profs_arr)

  +n0 = H.list_get_str(turmas, 0, "?")
  +n1 = H.list_get_str(turmas, 1, "?")
  +n2 = H.list_get_str(turmas, 2, "?")
  +s0 = H.collect_turma_slots(discs, n0, 1)
  +s1 = H.collect_turma_slots(discs, n1, 1)
  +s2 = H.collect_turma_slots(discs, n2, 1)

  # --- extracao do JSON ---
  +t1 = Nat.is_eq(List.length(&2, String, turmas), 3n)
  +t2 = Nat.is_eq(List.length(&2, H.DiscEntry, discs), 15n)
  +t3 = Nat.is_eq(List.length(&2, J.Json, profs_arr), 5n)
  +t4 = String.eq(n0, "T-A")
  +t5 = Nat.is_eq(List.length(&2, U32, s0), 20n)
  +t6 = Nat.is_eq(List.length(&2, U32, s1), 20n)
  +t7 = Nat.is_eq(List.length(&2, U32, s2), 20n)
  +t8 = Nat.is_eq(List.length(&2, U32, disc_profs), 15n)
  +t9 = all_positive(disc_profs)

  # --- mascaras de indisponibilidade ---
  +t10 = U32.is_eq(mask_at(masks, 0, 999), 1)        # P0: so o slot 0 bloqueado
  +t11 = U32.is_eq(mask_at(masks, 1, 999), 0)        # P1: totalmente livre
  +t12 = U32.is_eq(H.prof_horarios_to_mask(None{}), 1048575) # sem "horarios": tudo bloqueado

  # --- validacao: o fixture e valido ---
  +errs_ok = H.validate_input(turmas, discs, disc_profs, 3n, 15n, 5n, n0, n1, n2, 20n, 20n, 20n)
  +t13 = Nat.is_eq(List.length(&2, String, errs_ok), 0n)

  # --- validacao: cada checagem tem que ACUSAR ---
  +t14 = Nat.is_eq(List.length(&2, String, H.check_aulas([mk_disc("X", "T-A", 6)])), 1n)
  +t15 = Nat.is_eq(List.length(&2, String, H.check_aulas([mk_disc("X", "T-A", 0)])), 1n)
  +t16 = Nat.is_eq(List.length(&2, String, H.check_aulas([mk_disc("X", "T-A", 4)])), 0n)
  +t17 = Nat.is_eq(List.length(&2, String, H.check_slots("T-A", 18n)), 1n)
  +t18 = Nat.is_eq(List.length(&2, String, H.check_slots("T-A", 20n)), 0n)
  +t19 = Nat.is_eq(List.length(&2, String,
    H.check_disc_turmas([mk_disc("X", "T-INEXISTENTE", 4)], ["T-A", "T-B", "T-C"])), 1n)
  +t20 = Nat.is_eq(List.length(&2, String,
    H.check_disc_turmas([mk_disc("X", "T-B", 4)], ["T-A", "T-B", "T-C"])), 0n)
  +t21 = Nat.is_eq(List.length(&2, String,
    H.check_disc_profs([mk_disc("X", "T-A", 4)], [0])), 1n)
  +t22 = Nat.is_eq(List.length(&2, String,
    H.check_disc_profs([mk_disc("X", "T-A", 4)], [3])), 0n)

  +n = (fail_count(t1) + fail_count(t2) + fail_count(t3) + fail_count(t4) +
        fail_count(t5) + fail_count(t6) + fail_count(t7) + fail_count(t8) +
        fail_count(t9) + fail_count(t10) + fail_count(t11) + fail_count(t12) +
        fail_count(t13) + fail_count(t14) + fail_count(t15) + fail_count(t16) +
        fail_count(t17) + fail_count(t18) + fail_count(t19) + fail_count(t20) +
        fail_count(t21) + fail_count(t22) : U32)

  line(t1,  "load_turmas_names devolve 3 turmas") ++
  line(t2,  "load_disciplinas devolve 15 disciplinas") ++
  line(t3,  "professores[] tem 5 itens") ++
  line(t4,  "primeira turma e \"T-A\"") ++
  line(t5,  "collect_turma_slots(T-A) soma 20 aulas") ++
  line(t6,  "collect_turma_slots(T-B) soma 20 aulas") ++
  line(t7,  "collect_turma_slots(T-C) soma 20 aulas") ++
  line(t8,  "build_disc_profs devolve 15 mapeamentos") ++
  line(t9,  "nenhuma disciplina ficou sem professor (pid > 0)") ++
  line(t10, "mascara de P0 (indisponivel em seg/tempo 1) == 1") ++
  line(t11, "mascara de P1 (sempre disponivel) == 0") ++
  line(t12, "professor sem \"horarios\" fica totalmente bloqueado") ++
  line(t13, "validate_input aceita o fixture sem nenhum erro") ++
  line(t14, "check_aulas ACUSA aulas=6") ++
  line(t15, "check_aulas ACUSA aulas=0") ++
  line(t16, "check_aulas aceita aulas=4") ++
  line(t17, "check_slots ACUSA turma com 18 aulas") ++
  line(t18, "check_slots aceita turma com 20 aulas") ++
  line(t19, "check_disc_turmas ACUSA disciplina orfa") ++
  line(t20, "check_disc_turmas aceita turma existente") ++
  line(t21, "check_disc_profs ACUSA pid == 0") ++
  line(t22, "check_disc_profs aceita pid > 0") ++
  "Falhas: " ++ U32.show(n) ++ "\n" ++
  verdict(n)

def run_checks.root(fd_m: Maybe<&2, J.Json>) -> String:
  match fd_m:
    case None{}:
      "  [FALHA] fixture sem formData\nFalhas: 1\nHOUVE FALHAS\n"
    case Some{+fd}:
      run_checks.fd(fd)

# `match` nao escrutina valor computado, entao o ParseRes entra como parametro.
def run_checks(r: J.ParseRes) -> String:
  match r:
    case J.PFail{msg}:
      "  [FALHA] fixture embutido nao parseia: " ++ msg ++ "\nFalhas: 1\nHOUVE FALHAS\n"
    case J.POk{root}:
      run_checks.root(J.Json.get(root, "formData"))

def main() -> IO(Unit):
  IO.print(
    "=== TESTES DE CARGA DINAMICA E VALIDACAO ===\n" ++
    run_checks(J.parse_json(fixture()))
  )
