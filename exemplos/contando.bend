import Base

# Função recursiva que usa IO para imprimir conforme vai contando
# O combustivel Nat vai decrescendo a cada chamada, para respeitar a garantia de que a função irá parar eventualmente
# Já o contador U32 é usado para exibir o número atual e fazer a contagem de fato
def contar(+combustivel: Nat, +contador: U32) -> IO(Unit):
  match combustivel:
    # Caso base: imprime e para
    case 0n:
      IO.print(U32.show(contador))
    case 1n+p:
      # def IO.bind(-A: Type, -B: Type, m: IO(A), f: A -> IO(B)) -> IO(B):
      # f é um lambda que retorna a próxima sequência de ações
      IO.bind(Unit, Unit, 
        IO.print(U32.show(contador)),        # 1. Ação atual: imprime o contador
        u => contar(p, (contador + 1 : U32)) # 2. Próxima ação: chama contar recursivamente
      )
  
def main() -> IO(Unit):
  # Não é possível escrever um loop infinito, mas podemos fazer um loop longo o suficiente...
  # Mas se você escrever 4294967295n vai consumir toda a memória do seu computador
  # Desse jeito aqui Nat é avaliado lazy
  # max = U32.to_nat(4294967295)

  max = U32.to_nat(10)

  # A FAZER: verificar se deixar rodando isso vai ficando mesmo mais lento e consumindo mais memória
  contar(max, 0)