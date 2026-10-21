import Base
import ./../utils/io.bend as IOU

# MAP e SET da Base: dicionários com chave String.
#
#   Map.new(&2, V)                   um mapa vazio (valores V, Data)
#   Map.set(&2, V, m, chave, v)      -> Map         (insere ou troca)
#   Map.get(V, padrao, m, chave)     -> Map & V     (o mapa volta junto!)
#   Map.has(&2, V, m, chave)         -> Map & Bool
#   Map.to_list(&2, V, m)            -> lista de pares (chave, valor)
#   Set.new(), Set.add, Set.has, Set.size, Set.to_list, Set.from_list
#
# Como um Array, uma leitura devolve o mapa junto com a resposta, e o par só
# se abre como parâmetro de um auxiliar.

# Conta uma palavra: lê a contagem atual (0 se não houver) e grava +1
def conta.poe(r: Map<&2, U32> & U32, +palavra: String) -> Map<&2, U32>:
  (m, n) = r
  Map.set(&2, U32, m, palavra, (n + 1 : U32))

def contar(palavras: List<&2, String>, m: Map<&2, U32>) -> Map<&2, U32>:
  match palavras:
    case Nil{}: m
    case +p <> resto: contar(resto, conta.poe(Map.get(U32, 0, m, p), p))

# Os pares do `Map.to_list` são `Data` (podem ser duplicados). `A & B` é o par
# afim (`Type`); o par Data se escreve por extenso, então ganha um nome: uma
# def que devolve um TIPO (é assim que a Base define `Set()`).
def Entrada() -> Data:
  Sigma<&2, &2, String, _ => U32>

def mostra_par(par: Entrada()) -> String:
  (palavra, n) = par
  palavra ++ ": " ++ U32.show(n)

def mostra_busca(r: Map<&2, U32> & U32, palavra: String) -> String:
  (m, n) = r
  "\"" ++ palavra ++ "\" aparece " ++ U32.show(n) ++ " vez(es)"

def mostra_tem(r: Set() & Bool, palavra: String) -> String:
  (s, tem) = r
  "tem \"" ++ palavra ++ "\"? " ++ Bool.show(tem)

def nao_vazia(s: String) -> Bool:
  Bool.not(String.is_empty(s))

def padrao() -> String:
  "o rato roeu a roupa do rei de roma e a rainha de raiva roeu o resto"

# Uso: mapas [texto...]
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    +texto : String = Bool.pick(String, List.is_empty(&2, String, ts), padrao(), String.join(ts, " "))
    +palavras : List<&2, String> = List.filter(~String, ~nao_vazia, String.split(String.to_lower(texto), ' '))
    +freq : Map<&2, U32> = contar(palavras, Map.new(&2, U32))
    +distintas : Set() = Set.from_list(palavras)
    IO.print("texto: " ++ texto)
    IO.print(Nat.show(List.length(&2, String, palavras)) ++ " palavras, " ++ Nat.show(Set.size(distintas)) ++ " distintas")
    IO.print("frequências: " ++ List.show(~&2, ~Entrada(), ~mostra_par, Map.to_list(&2, U32, freq)))
    IO.print(mostra_busca(Map.get(U32, 0, freq, "roeu"), "roeu"))
    IO.print(mostra_tem(Set.has(distintas, "rainha"), "rainha"))
