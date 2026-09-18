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

# Tabela disc_id -> valor, indexada a partir de 1 como no solver.
def mk_t32(l: List<&2, U32>) -> H.Table32:
  H.fill_table32(l, H.empty_t32(), 1)

def mk_t16(l: List<&2, U32>) -> H.Table16:
  H.fill_table16(l, H.empty_t16(), 1)

# slot_unavail e indexada a partir de 0, nao de 1
def mk_t16_0(l: List<&2, U32>) -> H.Table16:
  H.fill_table16(l, H.empty_t16(), 0)

def mk_disc(nome: String, turma: String, aulas: U32) -> H.DiscEntry:
  H.DEntry{nome, turma, aulas, 2, 0}

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

  # --- agrupamento: run_penalty segue horario_genetic.rs ---
  # ideal = g quando divisivel, senao o multiplo de g mais proximo de len
  # (arredondando a metade para longe de zero, como o f64::round() do Rust).
  +t23 = U32.is_eq(H.run_penalty(4, 8), 0)     # bloco exato
  +t24 = U32.is_eq(H.run_penalty(2, 4), 0)
  +t25 = U32.is_eq(H.run_penalty(2, 8), 40)    # 2 aulas onde o ideal sao 4
  +t26 = U32.is_eq(H.run_penalty(1, 4), 20)    # ideal = round(0.5)*2 = 2
  +t27 = U32.is_eq(H.run_penalty(3, 4), 20)    # ideal = round(1.5)*2 = 4
  +t28 = U32.is_eq(H.run_penalty(6, 4), 0)     # multiplo de g: sem penalidade
  +t29 = U32.is_eq(H.run_penalty(6, 5), 80)    # divisivel: ideal fixo = g = 2
  +t30 = U32.is_eq(H.run_penalty(7, 0), 0)     # agrupar = 0 desliga a regra

  # --- varredura de blocos num dia de 4 tempos ---
    # disc_info: mascara de professores nos bits 0-15 e agrupar*2+dividir nos 16-23.
  # discs 1, 2 e 4 com agrupar=2; disc 3 com agrupar=4; dividir 0 em todas.
  # (prof 1 = mascara 1; agrupar*2 nos bits 16+: 4*65536=262144, 8*65536=524288)
  +gt = mk_t32([262145, 262145, 524289, 262145])
  +t31 = U32.is_eq(H.eval_day_grouping(H.make_d4(1, 1, 2, 2), gt), 0)
  +t32 = U32.is_eq(H.eval_day_grouping(H.make_d4(1, 2, 3, 4), gt), 80)  # 4 blocos de 1
  +t33 = U32.is_eq(H.eval_day_grouping(H.make_d4(3, 3, 3, 3), gt), 0)    # bloco de 4, g=4
  +t34 = U32.is_eq(H.eval_day_grouping(H.make_d4(3, 3, 1, 1), gt), 40)   # disc 3 parte ao meio
  +t35 = U32.is_eq(H.eval_day_grouping(H.make_d4(1, 1, 1, 2), gt), 40)   # bloco de 3 com g=2

  # --- empacotamento prof + agrupamento na mesma palavra ---
  # disciplina com professores {1,2,3} (mascara 7), agrupar=4, dividir=0:
  # 7 + 8*65536 = 524295
  +info1 = mk_t32([524295])
  +t36 = U32.is_eq(H.disc_pmask(info1, 1), 7)
  +t37 = U32.is_eq(H.disc_group(info1, 1), 8)
  +t38 = U32.is_eq(H.disc_pmask(info1, 2), 0)   # fora da tabela: sem professor
  +t39 = U32.is_eq(H.disc_group(info1, 2), 0)   # fora da tabela: regra desligada
  +t40 = Nat.is_eq(List.length(&2, String,
    H.check_agrupar([H.DEntry{"X", "T-A", 4, 200, 0}])), 1n)
  +t41 = Nat.is_eq(List.length(&2, String,
    H.check_agrupar([H.DEntry{"X", "T-A", 4, 4, 0}])), 0n)

  # --- choque de professor: conjuntos de professores + contagem acumulada ---
  # Professor i ocupa o bit i-1: prof 1 -> 1, prof 2 -> 2, prof 3 -> 4.
  +t42 = U32.is_eq(H.eval_prof_slot(1, 2, 4, 0), 0)     # 3 professores distintos
  +t43 = U32.is_eq(H.eval_prof_slot(1, 1, 4, 0), 100)   # 2 turmas disputam o prof 1
  +t44 = U32.is_eq(H.eval_prof_slot(1, 1, 1, 0), 300)   # 3 turmas disputam (antes: 150)
  +t45 = U32.is_eq(H.eval_prof_slot(1, 0, 0, 0), 0)     # sem disputa, sem penalidade
  +t46 = U32.is_eq(H.eval_prof_slot(0, 0, 0, 0), 0)     # slot sem professor algum
  +t47 = U32.is_eq(H.eval_prof_slot(1, 0, 0, 1), 50)    # prof 1 indisponivel
  +t48 = U32.is_eq(H.eval_prof_slot(1, 1, 0, 1), 200)   # indisponivel E disputado
  +t49 = U32.is_eq(H.eval_prof_slot(1, 1, 1, 1), 450)   # indisponivel e disputado por 3
  # Disciplina com DOIS professores ({1,2} = mascara 3) contra uma com so o 2:
  # o professor 2 fica disputado por duas turmas, o 1 nao. Era invisivel antes,
  # quando so o primeiro professor de cada disciplina contava.
  +t50 = U32.is_eq(H.eval_prof_slot(3, 2, 0, 0), 100)
  +t51 = U32.is_eq(H.eval_prof_slot(3, 3, 0, 0), 200)   # os dois professores disputados
  +t52 = U32.is_eq(H.eval_prof_slot(3, 4, 0, 0), 0)     # nenhum professor em comum

  # --- indisponibilidade transposta: 2 slots por palavra ---
  # palavra 0 = slot 0 nos bits 0-15, slot 1 nos bits 16-31
  +su = mk_t16_0([131073])   # slot 0 -> {prof 1}, slot 1 -> {prof 2}
  +t53 = U32.is_eq(H.slot_unavail_get(su, 0), 1)
  +t54 = U32.is_eq(H.slot_unavail_get(su, 1), 2)
  +t55 = U32.is_eq(H.slot_unavail_get(su, 2), 0)

  +n = (fail_count(t42) + fail_count(t43) + fail_count(t44) + fail_count(t45) +
        fail_count(t46) + fail_count(t47) + fail_count(t48) + fail_count(t49) +
        fail_count(t50) + fail_count(t51) + fail_count(t52) +
        fail_count(t53) + fail_count(t54) + fail_count(t55) +
        fail_count(t36) + fail_count(t37) + fail_count(t38) + fail_count(t39) +
        fail_count(t40) + fail_count(t41) +
        fail_count(t23) + fail_count(t24) + fail_count(t25) + fail_count(t26) +
        fail_count(t27) + fail_count(t28) + fail_count(t29) + fail_count(t30) +
        fail_count(t31) + fail_count(t32) + fail_count(t33) + fail_count(t34) +
        fail_count(t35) +
        fail_count(t1) + fail_count(t2) + fail_count(t3) + fail_count(t4) +
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
  line(t23, "run_penalty: bloco de 4 com agrupar=4 nao penaliza") ++
  line(t24, "run_penalty: bloco de 2 com agrupar=2 nao penaliza") ++
  line(t25, "run_penalty: bloco de 2 com agrupar=4 custa 40") ++
  line(t26, "run_penalty: bloco de 1 com agrupar=2 custa 20 (round meio p/ cima)") ++
  line(t27, "run_penalty: bloco de 3 com agrupar=2 custa 20") ++
  line(t28, "run_penalty: bloco de 6 com agrupar=2 nao penaliza (multiplo)") ++
  line(t29, "run_penalty: com dividir=1 o ideal fica fixo em g") ++
  line(t30, "run_penalty: agrupar=0 desliga a regra") ++
  line(t31, "eval_day_grouping: [1,1,2,2] com g=2 nao penaliza") ++
  line(t32,"eval_day_grouping: [1,2,3,4] custa 4 blocos de 1") ++
  line(t33, "eval_day_grouping: [3,3,3,3] com g=4 nao penaliza") ++
  line(t34, "eval_day_grouping: [3,3,1,1] penaliza o bloco partido de g=4") ++
  line(t35, "eval_day_grouping: [1,1,1,2] penaliza o bloco de 3 com g=2") ++
  line(t36, "disc_info: disc_pmask extrai o conjunto de professores dos bits 0-15") ++
  line(t37, "disc_info: disc_group extrai agrupar/dividir dos bits 16-23") ++
  line(t38, "disc_info: indice fora da tabela nao tem professor") ++
  line(t39, "disc_info: indice fora da tabela tem a regra desligada") ++
  line(t40, "check_agrupar ACUSA agrupar=200 (nao cabe em 7 bits)") ++
  line(t41, "check_agrupar aceita agrupar=4") ++
  line(t42, "eval_prof_slot: 3 professores distintos nao penalizam") ++
  line(t43, "eval_prof_slot: 2 turmas no mesmo professor custam 100") ++
  line(t44, "eval_prof_slot: 3 turmas no mesmo professor custam 300") ++
  line(t45, "eval_prof_slot: professor unico e disponivel nao penaliza") ++
  line(t46, "eval_prof_slot: slot sem professor nao penaliza") ++
  line(t47, "eval_prof_slot: professor indisponivel custa 50") ++
  line(t48, "eval_prof_slot: indisponivel E disputado custa 200") ++
  line(t49, "eval_prof_slot: indisponivel e disputado por 3 custa 450") ++
  line(t50, "eval_prof_slot: 2o professor de uma disciplina TAMBEM conta") ++
  line(t51, "eval_prof_slot: dois professores em comum penalizam os dois") ++
  line(t52, "eval_prof_slot: disciplinas sem professor em comum nao penalizam") ++
  line(t53, "slot_unavail_get: slot par sai dos bits 0-15") ++
  line(t54, "slot_unavail_get: slot impar sai dos bits 16-31") ++
  line(t55, "slot_unavail_get: slot sem indisponibilidade devolve 0") ++
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
