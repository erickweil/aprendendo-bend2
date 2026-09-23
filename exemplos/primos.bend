# Pior jeito que existe de verificar primo em Bend2, pois não é lazy e o pick executa os dois lados
import Base
import ./../utils/io.bend as IOUtils

def eh_divisivel(n: U32, d: U32) -> Bool:
  U32.is_zero((n % d : U32))

def eh_primo.go(n: Nat, cond: Bool, +i: U32, +num: U32) -> Bool:
  match n cond:
    case 0n _: 
      True{}
    case 1n+p True{}:
      # Deve parar pois é divisível, então não é primo
      False{}
    case 1n+p False{}:
      match i:
        case 0:
          # Deve parar pois i*i > num, então não é divisível por nenhum número menor que a raiz, então é primo
          True{}
        case i:
          # Manda 0 para sinalizar que i > sqrt(num)
          next = Bool.pick(U32, (i > num / i : U32), 0, (i + 2 : U32))
          eh_primo.go(p, eh_divisivel(num, i), next, num)

def eh_primo(+num: U32) -> Bool:
  match num:
    # Menores que 2 não são primos
    case 0:
      False{}
    case 1:
      False{}
    # 2 é primo
    case 2:
      True{}
    case num:
      eh_primo.go(U32.to_nat((num / 2 : U32)), eh_divisivel(num, 2), 3, num)

# Irá contar quantos números primos existem
def contar_primos.go(n: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      # Sequencial
      # Soma + 1 se o número for primo, ou + 0 se não for
      # acc = (acc + Bool.pick(U32, eh_primo(i), 1, 0) : U32)
      # contar_primos.go(p, (i + 1 : U32), acc)

      # Paralelo (A FAZER)
      a b = 
        contar_primos.go(p, (i + 1 : U32), 0) 
        contar_primos.go(p, (i + 1 : U32), 0)
      
      (acc + a + b : U32)

def contar_primos(+inicio: U32, fim: U32) -> U32:
  contar_primos.go(U32.to_nat((fim - inicio : U32)), inicio, 0)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = IOUtils.num_at(IOUtils.numbers(args), 0n, 100)
    u : Unit <- IO.print("Contando primos de 0 até " ++ U32.show(n) ++ "...")
    IO.print("Encontrados: " ++ U32.show(contar_primos(0, n)))
    # IO.print(Bool.pick(String, eh_primo(n), 
    #   "Primo", 
    #   "Não é primo"
    # ))