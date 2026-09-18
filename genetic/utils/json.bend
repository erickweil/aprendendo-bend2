import Base

# ==============================================================================
# BEND 2 REUSABLE JSON PARSER & SERIALIZER (genetic/utils/json.bend)
# ==============================================================================
# Parser JSON modular de 2 fases (Tokenizer Linear + Autômato com Pilha de Tokens)
# para Bend 2.
#
# Propriedades de Engenharia & Segurança:
# 1. Zero recursão mútua proibida (evita erros do verificador estático do Bend 2).
# 2. Tokenizador linear em def único autônomo com modos rasos (TokMode).
#    ATENÇÃO: marcado @unsafe — sua terminação NÃO é verificada pelo compilador.
# 3. Autômato com pilha guiado por fuel indutivo estrutural (fuel: Nat).
#    O fuel garante terminação de `parse_pda` (e só dele), impossibilitando
#    loop infinito ou consumo descontrolado de memória (OOM) na fase de parsing.
# 4. Suporte a tipos: Null, Bool, Num, Str, Arr, Obj.
#    LIMITAÇÕES: sem sequências de escape (\" e \n dentro de strings), sem
#    números negativos e sem ponto flutuante — todo número é lido como U32.
# 5. Utilitários ergonômicos: Json.get, Json.get_str, Json.get_num, Json.get_arr.
# 6. Serializador recíproco Json.stringify com fuel bounded.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. AST JSON
# ------------------------------------------------------------------------------

type Json is Data:
  JNull{}
  JBool{val: Bool}
  JNum{val: U32}
  JStr{val: String}
  JArr{items: List<&2, Json>}
  JObj{keys: List<&2, String>, vals: List<&2, Json>}

type ParseRes is Data:
  POk{val: Json}
  PFail{msg: String}

# ------------------------------------------------------------------------------
# 2. TOKENIZADOR LINEAR
# ------------------------------------------------------------------------------

type Token is Data:
  TokLBrace{}
  TokRBrace{}
  TokLBracket{}
  TokRBracket{}
  TokColon{}
  TokComma{}
  TokStr{val: String}
  TokNum{val: U32}
  TokBool{val: Bool}
  TokNull{}

type TokMode is Data:
  TokDefault{}
  TokInStr{acc: String}
  TokInNum{acc: U32}

@unsafe def tokenize(mode: TokMode, s: String) -> List<&2, Token>:
  match mode:
    case TokDefault{}:
      match s:
        case SNil{}:
          Nil{}
        case SCon{Chr{c}, t}:
          match c:
            case 32: tokenize(TokDefault{}, t)
            case 9:  tokenize(TokDefault{}, t)
            case 10: tokenize(TokDefault{}, t)
            case 13: tokenize(TokDefault{}, t)
            case 123: TokLBrace{} <> tokenize(TokDefault{}, t)
            case 125: TokRBrace{} <> tokenize(TokDefault{}, t)
            case 91:  TokLBracket{} <> tokenize(TokDefault{}, t)
            case 93:  TokRBracket{} <> tokenize(TokDefault{}, t)
            case 58:  TokColon{} <> tokenize(TokDefault{}, t)
            case 44:  TokComma{} <> tokenize(TokDefault{}, t)
            case 34:  tokenize(TokInStr{""}, t)
            case 48:  tokenize(TokInNum{0}, t)
            case 49:  tokenize(TokInNum{1}, t)
            case 50:  tokenize(TokInNum{2}, t)
            case 51:  tokenize(TokInNum{3}, t)
            case 52:  tokenize(TokInNum{4}, t)
            case 53:  tokenize(TokInNum{5}, t)
            case 54:  tokenize(TokInNum{6}, t)
            case 55:  tokenize(TokInNum{7}, t)
            case 56:  tokenize(TokInNum{8}, t)
            case 57:  tokenize(TokInNum{9}, t)
            case 116: TokBool{True{}} <> tokenize(TokDefault{}, String.drop(t, 3n))
            case 102: TokBool{False{}} <> tokenize(TokDefault{}, String.drop(t, 4n))
            case 110: TokNull{} <> tokenize(TokDefault{}, String.drop(t, 3n))
            case _:   tokenize(TokDefault{}, t)

    case TokInStr{+acc}:
      match s:
        case SNil{}:
          TokStr{String.reverse(acc)} <> Nil{}
        case SCon{Chr{c}, t}:
          match c:
            case 34: TokStr{String.reverse(acc)} <> tokenize(TokDefault{}, t)
            case _:  tokenize(TokInStr{SCon{Chr{c}, acc}}, t)

    case TokInNum{+acc}:
      match s:
        case SNil{}:
          TokNum{acc} <> Nil{}
        case SCon{Chr{c}, t}:
          match c:
            case 48: tokenize(TokInNum{(acc * 10 + 0 : U32)}, t)
            case 49: tokenize(TokInNum{(acc * 10 + 1 : U32)}, t)
            case 50: tokenize(TokInNum{(acc * 10 + 2 : U32)}, t)
            case 51: tokenize(TokInNum{(acc * 10 + 3 : U32)}, t)
            case 52: tokenize(TokInNum{(acc * 10 + 4 : U32)}, t)
            case 53: tokenize(TokInNum{(acc * 10 + 5 : U32)}, t)
            case 54: tokenize(TokInNum{(acc * 10 + 6 : U32)}, t)
            case 55: tokenize(TokInNum{(acc * 10 + 7 : U32)}, t)
            case 56: tokenize(TokInNum{(acc * 10 + 8 : U32)}, t)
            case 57: tokenize(TokInNum{(acc * 10 + 9 : U32)}, t)
            case _:  TokNum{acc} <> tokenize(TokDefault{}, SCon{Chr{c}, t})

# ------------------------------------------------------------------------------
# 3. PARSER: AUTÔMATO COM PILHA SOBRE TOKENS (TOKEN PDA)
# ------------------------------------------------------------------------------

type TokFrame is Data:
  InArr{items: List<&2, Json>}
  InObj{keys: List<&2, String>, vals: List<&2, Json>}
  InObjVal{key: String, keys: List<&2, String>, vals: List<&2, Json>}

type TokStack is Data:
  TStackNil{}
  TStackCons{frame: TokFrame, tail: TokStack}

def parse_pda(fuel: Nat, in_reduce: Bool, toks: List<&2, Token>, stack: TokStack, v: Json) -> ParseRes:
  match fuel:
    case 0n:
      PFail{"Parser fuel exhausted"}
    case 1n+p:
      match in_reduce:
        case False{}:
          match toks:
            case Nil{}: PFail{"Unexpected EOF expecting value"}
            case tok <> rest:
              match tok:
                case TokStr{s}: parse_pda(p, True{}, rest, stack, JStr{s})
                case TokNum{n}: parse_pda(p, True{}, rest, stack, JNum{n})
                case TokBool{b}: parse_pda(p, True{}, rest, stack, JBool{b})
                case TokNull{}: parse_pda(p, True{}, rest, stack, JNull{})
                case TokLBracket{}: parse_pda(p, False{}, rest, TStackCons{InArr{Nil{}}, stack}, JNull{})
                case TokLBrace{}: parse_pda(p, False{}, rest, TStackCons{InObj{Nil{}, Nil{}}, stack}, JNull{})
                case TokRBracket{}:
                  match stack:
                    case TStackNil{}: PFail{"Unexpected ']' at root"}
                    case TStackCons{frame, tail}:
                      match frame:
                        case InArr{items}:
                          match items:
                            case Nil{}: parse_pda(p, True{}, rest, tail, JArr{Nil{}})
                            case _ <> _: PFail{"Unexpected ']'"}
                        case _: PFail{"Unexpected ']' in object"}
                case TokRBrace{}:
                  match stack:
                    case TStackNil{}: PFail{"Unexpected '}' at root"}
                    case TStackCons{frame, tail}:
                      match frame:
                        case InObj{keys, vals}:
                          match keys:
                            case Nil{}: parse_pda(p, True{}, rest, tail, JObj{Nil{}, Nil{}})
                            case _ <> _: PFail{"Unexpected '}'"}
                        case _: PFail{"Unexpected '}' in array"}
                case _: PFail{"Expected value"}
        case True{}:
          match toks:
            case Nil{}:
              match stack:
                case TStackNil{}: POk{v}
                case TStackCons{_, _}: PFail{"Unexpected EOF: unclosed containers"}
            case tok <> rest:
              match tok:
                case TokComma{}:
                  match stack:
                    case TStackNil{}: PFail{"Unexpected comma at root"}
                    case TStackCons{frame, tail}:
                      match frame:
                        case InArr{items}: parse_pda(p, False{}, rest, TStackCons{InArr{v <> items}, tail}, JNull{})
                        case InObjVal{key, keys, vals}: parse_pda(p, False{}, rest, TStackCons{InObj{key <> keys, v <> vals}, tail}, JNull{})
                        case InObj{_, _}: PFail{"Unexpected comma before key"}
                case TokColon{}:
                  match stack:
                    case TStackNil{}: PFail{"Unexpected colon at root"}
                    case TStackCons{frame, tail}:
                      match frame:
                        case InObj{keys, vals}:
                          match v:
                            case JStr{key}: parse_pda(p, False{}, rest, TStackCons{InObjVal{key, keys, vals}, tail}, JNull{})
                            case _: PFail{"Object key must be string"}
                        case _: PFail{"Unexpected colon outside object"}
                case TokRBracket{}:
                  match stack:
                    case TStackNil{}: PFail{"Unexpected ']' at root"}
                    case TStackCons{frame, tail}:
                      match frame:
                        case InArr{items}: parse_pda(p, True{}, rest, tail, JArr{List.reverse(&2, Json, v <> items)})
                        case _: PFail{"Unexpected ']' outside array"}
                case TokRBrace{}:
                  match stack:
                    case TStackNil{}: PFail{"Unexpected '}' at root"}
                    case TStackCons{frame, tail}:
                      match frame:
                        case InObjVal{key, keys, vals}: parse_pda(p, True{}, rest, tail, JObj{List.reverse(&2, String, key <> keys), List.reverse(&2, Json, v <> vals)})
                        case _: PFail{"Unexpected '}' outside object"}
                case _: PFail{"Unexpected token in reduce"}

def parse_json(s: String) -> ParseRes:
  +toks = tokenize(TokDefault{}, s)
  +fuel = Nat.add(List.length(&2, Token, toks), 10n)
  parse_pda(fuel, False{}, toks, TStackNil{}, JNull{})

# ------------------------------------------------------------------------------
# 4. CONSULTA ERGONÔMICA NO AST JSON
# ------------------------------------------------------------------------------

def Json.find_key(keys: List<&2, String>, vals: List<&2, Json>, +target: String) -> Maybe<&2, Json>:
  match keys:
    case Nil{}:
      None{}
    case +k <> kt:
      match vals:
        case Nil{}:
          None{}
        case +v <> vt:
          Bool.pick(Maybe<&2, Json>, String.eq(k, target), Some{v}, Json.find_key(kt, vt, target))

def Json.get(j: Json, target: String) -> Maybe<&2, Json>:
  match j:
    case JObj{keys, vals}:
      Json.find_key(keys, vals, target)
    case _:
      None{}

def Json.get_str.step(m: Maybe<&2, Json>, default: String) -> String:
  match m:
    case None{}: default
    case Some{val}:
      match val:
        case JStr{s}: s
        case _: default

def Json.get_str(j: Json, key: String, default: String) -> String:
  Json.get_str.step(Json.get(j, key), default)

def Json.get_num.step(m: Maybe<&2, Json>, default: U32) -> U32:
  match m:
    case None{}: default
    case Some{val}:
      match val:
        case JNum{n}: n
        case _: default

def Json.get_num(j: Json, key: String, default: U32) -> U32:
  Json.get_num.step(Json.get(j, key), default)

def Json.get_arr.step(m: Maybe<&2, Json>) -> List<&2, Json>:
  match m:
    case None{}: Nil{}
    case Some{val}:
      match val:
        case JArr{items}: items
        case _: Nil{}

def Json.get_arr(j: Json, key: String) -> List<&2, Json>:
  Json.get_arr.step(Json.get(j, key))

# ------------------------------------------------------------------------------
# 5. SERIALIZADOR JSON (Json.stringify)
# ------------------------------------------------------------------------------

type StrMode is Data:
  ModeVal{j: Json}
  ModeArr{items: List<&2, Json>}
  ModeObj{keys: List<&2, String>, vals: List<&2, Json>}

# JSON exige os literais em minúsculas (RFC 8259 secao 3). `Bool.show` devolve
# "True"/"False", que nao e JSON valido e nem sequer volta pelo nosso tokenizer.
def json_bool_lit(b: Bool) -> String:
  match b:
    case True{}: "true"
    case False{}: "false"

def stringify_step(fuel: Nat, m: StrMode) -> String:
  match fuel:
    case 0n: ""
    case 1n+ +p:
      match m:
        case ModeVal{j}:
          match j:
            case JNull{}: "null"
            case JBool{b}: json_bool_lit(b)
            case JNum{n}: U32.show(n)
            case JStr{s}: "\"" ++ s ++ "\""
            case JArr{items}: "[" ++ stringify_step(p, ModeArr{items}) ++ "]"
            case JObj{keys, vals}: "{" ++ stringify_step(p, ModeObj{keys, vals}) ++ "}"
        case ModeArr{items}:
          match items:
            case Nil{}: ""
            case h <> Nil{}: stringify_step(p, ModeVal{h})
            case h <> t: stringify_step(p, ModeVal{h}) ++ ", " ++ stringify_step(p, ModeArr{t})
        case ModeObj{keys, vals}:
          match keys:
            case Nil{}: ""
            case k <> Nil{}:
              match vals:
                case Nil{}: ""
                case v <> _: "\"" ++ k ++ "\": " ++ stringify_step(p, ModeVal{v})
            case k <> kt:
              match vals:
                case Nil{}: ""
                case v <> vt: "\"" ++ k ++ "\": " ++ stringify_step(p, ModeVal{v}) ++ ", " ++ stringify_step(p, ModeObj{kt, vt})

def Json.stringify(j: Json) -> String:
  stringify_step(500n, ModeVal{j})
