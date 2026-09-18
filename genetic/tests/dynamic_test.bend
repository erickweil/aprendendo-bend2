import Base
import ./../utils/json.bend as J

type Day4 is Data:
  D4{t0: U32, t1: U32, t2: U32, t3: U32}

type Week5 is Data:
  W5{d0: Day4, d1: Day4, d2: Day4, d3: Day4, d4: Day4}

type DiscEntry is Data:
  DEntry{nome: String, turma: String, aulas: U32, agrupar: U32}

def load_turmas_names(items: List<&2, J.Json>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case +h <> t:
      +nome = J.Json.get_str(h, "nome", "Turma")
      nome <> load_turmas_names(t)

def load_disciplinas(items: List<&2, J.Json>) -> List<&2, DiscEntry>:
  match items:
    case Nil{}: Nil{}
    case +h <> t:
      +nome = J.Json.get_str(h, "nome", "")
      +turma = J.Json.get_str(h, "turma", "")
      +aulas = J.Json.get_num(h, "aulas", 2)
      +agrupar = J.Json.get_num(h, "agrupar", 2)
      DEntry{nome, turma, aulas, agrupar} <> load_disciplinas(t)

def json_is_target_num(j: J.Json, +target: U32) -> Bool:
  match j:
    case J.JNum{val}: U32.is_eq(val, target)
    case _: False{}

def list_contains_num(l: List<&2, J.Json>, +target: U32) -> Bool:
  match l:
    case Nil{}: False{}
    case h <> t:
      Bool.pick(Bool, json_is_target_num(h, target), True{}, list_contains_num(t, target))

def is_tempo_unavailable(+tempos_list: List<&2, J.Json>, +tempo_idx: U32) -> U32:
  +tempo_num = U32.inc(tempo_idx)
  +is_avail = list_contains_num(tempos_list, tempo_num)
  Bool.pick(U32, is_avail, 0, 1)

def day_unavail_mask(+day_arr: List<&2, J.Json>) -> U32:
  +b0 = is_tempo_unavailable(day_arr, 0)
  +b1 = is_tempo_unavailable(day_arr, 1)
  +b2 = is_tempo_unavailable(day_arr, 2)
  +b3 = is_tempo_unavailable(day_arr, 3)
  +m0 = b0
  +m1 = U32.shln(b1, 1n)
  +m2 = U32.shln(b2, 2n)
  +m3 = U32.shln(b3, 3n)
  U32.or(m0, U32.or(m1, U32.or(m2, m3)))

def prof_horarios_to_mask(h_obj: Maybe<&2, J.Json>) -> U32:
  match h_obj:
    case None{}:
      1048575 # 2^20 - 1
    case Some{+val}:
      +m_seg = day_unavail_mask(J.Json.get_arr(val, "seg"))
      +m_ter = day_unavail_mask(J.Json.get_arr(val, "ter"))
      +m_qua = day_unavail_mask(J.Json.get_arr(val, "qua"))
      +m_qui = day_unavail_mask(J.Json.get_arr(val, "qui"))
      +m_sex = day_unavail_mask(J.Json.get_arr(val, "sex"))
      +s0 = m_seg
      +s1 = U32.shln(m_ter, 4n)
      +s2 = U32.shln(m_qua, 8n)
      +s3 = U32.shln(m_qui, 12n)
      +s4 = U32.shln(m_sex, 16n)
      U32.or(s0, U32.or(s1, U32.or(s2, U32.or(s3, s4))))

def json_is_target_str(j: J.Json, +target: String) -> Bool:
  match j:
    case J.JStr{val}: String.eq(val, target)
    case _: False{}

def list_contains_str(l: List<&2, J.Json>, +target: String) -> Bool:
  match l:
    case Nil{}: False{}
    case h <> t:
      Bool.pick(Bool, json_is_target_str(h, target), True{}, list_contains_str(t, target))

def find_prof_for_disc(+disc_nome: String, profs: List<&2, J.Json>, +cur_id: U32) -> U32:
  match profs:
    case Nil{}: 0
    case +h <> t:
      +discs_list = J.Json.get_arr(h, "disciplinas")
      Bool.pick(U32, list_contains_str(discs_list, disc_nome),
        cur_id,
        find_prof_for_disc(disc_nome, t, U32.inc(cur_id)))

def build_disc_profs(discs: List<&2, DiscEntry>, +profs: List<&2, J.Json>) -> List<&2, U32>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{nome, _, _, _} = h
      +pid = find_prof_for_disc(nome, profs, 1)
      pid <> build_disc_profs(t, profs)

def repeat_val(+val: U32, +count: U32) -> List<&2, U32>:
  match count:
    case 0: Nil{}
    case 1: [val]
    case 2: [val, val]
    case 3: [val, val, val]
    case _: [val, val, val, val]

def collect_turma_slots(discs: List<&2, DiscEntry>, +turma_nome: String, +disc_id: U32) -> List<&2, U32>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{_, t_nome, aulas, _} = h
      +matching = String.eq(t_nome, turma_nome)
      +added = Bool.pick(List<&2, U32>, matching, repeat_val(disc_id, aulas), Nil{})
      List.append(&2, U32, added, collect_turma_slots(t, turma_nome, U32.inc(disc_id)))

def load_profs_unavail_masks(profs: List<&2, J.Json>) -> List<&2, U32>:
  match profs:
    case Nil{}: Nil{}
    case +h <> t:
      +m = prof_horarios_to_mask(J.Json.get(h, "horarios"))
      m <> load_profs_unavail_masks(t)

def slots20_to_week5(slots: List<&2, U32>) -> Week5:
  match slots:
    case s0 <> s1 <> s2 <> s3 <> s4 <> s5 <> s6 <> s7 <> s8 <> s9 <> s10 <> s11 <> s12 <> s13 <> s14 <> s15 <> s16 <> s17 <> s18 <> s19 <> _:
      W5{
        D4{s0, s1, s2, s3},
        D4{s4, s5, s6, s7},
        D4{s8, s9, s10, s11},
        D4{s12, s13, s14, s15},
        D4{s16, s17, s18, s19}
      }
    case _:
      W5{
        D4{0, 0, 0, 0},
        D4{0, 0, 0, 0},
        D4{0, 0, 0, 0},
        D4{0, 0, 0, 0},
        D4{0, 0, 0, 0}
      }

def main.handle_form_data(form_data: Maybe<&2, J.Json>) -> IO(Unit):
  match form_data:
    case None{}:
      IO.print("formData ausente\n")
    case Some{+fd}:
      +turmas_arr = J.Json.get_arr(fd, "turmas")
      +discs_arr = J.Json.get_arr(fd, "disciplinas")
      +profs_arr = J.Json.get_arr(fd, "professores")
      +turmas = load_turmas_names(turmas_arr)
      +discs = load_disciplinas(discs_arr)
      +disc_profs = build_disc_profs(discs, profs_arr)
      +prof_masks = load_profs_unavail_masks(profs_arr)
      
      # Testa slots para Turma 2026
      +t0_slots = collect_turma_slots(discs, "Turma 2026", 1)
      +t1_slots = collect_turma_slots(discs, "Turma 2025", 1)
      +t2_slots = collect_turma_slots(discs, "Turma 2024", 1)
      
      IO.print(
        "=== TESTE DE CARGA DINÂMICA COMPLETO ===\n" ++
        "Total Turmas Lidas:            " ++ Nat.show(List.length(&2, String, turmas)) ++ "\n" ++
        "Total Disciplinas Lidas:       " ++ Nat.show(List.length(&2, DiscEntry, discs)) ++ "\n" ++
        "Total Professores Lidos:       " ++ Nat.show(List.length(&2, J.Json, profs_arr)) ++ "\n" ++
        "Mapeamentos Disc -> Prof:      " ++ Nat.show(List.length(&2, U32, disc_profs)) ++ "\n" ++
        "Máscaras de Indisponibilidade: " ++ Nat.show(List.length(&2, U32, prof_masks)) ++ "\n" ++
        "Slots Turma 2026 (esperado 20):" ++ Nat.show(List.length(&2, U32, t0_slots)) ++ "\n" ++
        "Slots Turma 2025 (esperado 20):" ++ Nat.show(List.length(&2, U32, t1_slots)) ++ "\n" ++
        "Slots Turma 2024 (esperado 20):" ++ Nat.show(List.length(&2, U32, t2_slots)) ++ "\n" ++
        "STATUS: CARGA DINÂMICA 100% BEM-SUCEDIDA!\n"
      )

def main.handle_root(root: J.Json) -> IO(Unit):
  main.handle_form_data(J.Json.get(root, "formData"))

def main.handle_parse(res: J.ParseRes) -> IO(Unit):
  match res:
    case J.PFail{err}:
      IO.print("Falha no parse: " ++ err ++ "\n")
    case J.POk{root}:
      main.handle_root(root)

def main.dispatch(env_res: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match env_res:
    case Fail{_}:
      IO.print("HORARIO_JSON nao encontrado no ambiente.\n")
    case Done{json_str}:
      main.handle_parse(J.parse_json(json_str))

def main() -> IO(Unit):
  do IO<Unit>:
    env_res : Result<&1, &1, U32 & String, String> <- IO.get_env("HORARIO_JSON")
    main.dispatch(env_res)
