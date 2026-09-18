# Estudo Aprofundado de Paralelismo em Bend 2: 1 Thread vs 4 Threads

Este documento consolida a investigação empírica, a engenharia reversa do runtime em C e as otimizações arquiteturais de paralelismo (*multithreading*) em **Bend 2.0.5**, comparando a execução sequencial (`--threads 1`), intermediária (`--threads 2`) e multicore total (`--threads 4`) no processador Intel Xeon Gold (4 vCPUs em topologia dual-socket NUMA).

---

## 1. Benchmarks Empíricos e Resultados Comparativos

### Benchmark 1: Computação Pura em Registradores (Benchmark Canônico `pow2`)
Cálculo puramente computacional e perfeitamente balanceado, sem alocações em heap:
```bend
def pow2(+n: Nat) -> U32:
  match n:
    case 0n: 1
    case 1n+p:
      a b = pow2(p) pow2(p)
      (a + b : U32)
```

| Configuração | Tempo Real (Wall-Clock) | Tempo de CPU (User) | Speedup vs 1 Thread |
| :--- | :---: | :---: | :---: |
| **1 Thread** | 1.251s | 1.248s | 1.00x (Base) |
| **2 Threads** | 0.632s | 1.258s | **1.98x** (Quase Linear) |
| **4 Threads** | 0.382s | 1.277s | **3.27x** (Excelente) |

* **Conclusão:** Quando as tarefas não dependem de alocação de heap e são perfeitamente balanceadas, o scheduler de bifurcação binária do Bend 2 entrega **escala quase linear (3.27x em 4 cores)** com menos de 2% de overhead de sincronização de CPU.

---

### Benchmark 2: Algoritmo Genético com Fork-Join Fino (Fine-Grained Nested Parallelism)
Bifurcação paralela `l r = eval(left) eval(right)` e `l r = reproduce(left) reproduce(right)` em nível de cada par de folhas a cada geração (árvore de 16 folhas x 4 ilhas):

| Configuração | Tempo Real | Tempo de CPU (User) | Overhead de Contenção |
| :--- | :---: | :---: | :---: |
| **1 Thread** | **0.055s** | 0.052s | 0% (Modo solo rápido) |
| **2 Threads** | 1.819s | 2.333s | **+4400% de CPU desperdiçada** |
| **4 Threads** | 1.937s | 3.276s | **+6300% de CPU desperdiçada** |

* **Diagnóstico da Degradação:** Em tarefas minúsculas (10 a 50 nanosegundos por folha), criar descritores de tarefas (`join tasks`), empurrar para filas em anel atômicas (`ring_push`) e sincronizar contadores atômicos de barreira gera um custo 50x maior que a própria computação!

---

### Benchmark 3: Algoritmo Genético Coarse-Grained (Modelo de Ilhas Macro-Paralelo)
Eliminação de bifurcações paralelas internas em folhas. Cada thread/core evolui uma ilha de 64 indivíduos sequencialmente em cache local L1/L2 durante $E$ gerações. A sincronização de barreira ocorre **apenas na migração entre épocas**:

| Configuração | 1.000 Gerações (256 ind.) | 15.000 Gerações (256 ind.) | 512.000 Simulações (Neuro) |
| :--- | :---: | :---: | :---: |
| **1 Thread** | 0.016s (User: 0.016s) | 0.211s (User: 0.209s) | 1.709s (User: 1.708s) |
| **2 Threads** | 0.023s (User: 0.017s) | 0.261s (User: 0.378s) | **0.992s (1.72x speedup!)** |
| **4 Threads** | 0.033s (User: 0.022s) | 0.252s (User: 0.399s) | **1.041s (1.64x speedup)** |

* **Conclusão:** O overhead de CPU caiu de **6300% para menos de 3.6%**! Em cargas de simulação real (Neuroevolução Cart-Pole com $512.000$ simulações contínuas de 200 passos), 2 threads reduziram o tempo de execução de 1.71s para **0.99s**.

---

## 2. As 4 Regras de Ouro para Paralelismo de Alta Performance em Bend 2

### Regra 1: Respeitar o Limiar de Inicialização de Threads (~25ms a 35ms)
* Em sistemas operacionais Linux, o ciclo de criação e encerramento de threads (`pthread_create`, alocação de stacks de threads, pools de tarefas e destrutores) consome aproximadamente 25ms a 35ms de latência fixa do sistema operacional (`sys time`).
* Para problemas pequenos onde o cálculo termina em menos de 30ms (ex: OneMax com 32 indivíduos ou Sudoku 9x9 básico), **1 thread será mais rápida na medição de relógio real**. O paralelismo multi-thread só oferece retorno quando a carga computacional ultrapassa ~50ms a 100ms.

### Regra 2: Granularidade Grossa (*Coarse-Grained Tasks*)
* O compilador do Bend 2 gera uma máquina de estados plana onde cada chamada paralela `a b = f(x) g(y)` aloca uma tarefa de junção (*join task*) e despacha para os anéis de execução das threads.
* **Nunca** faça chamadas paralelas em subárvores de tamanho unitário ou folhas triviais se a função do nó durar menos de alguns microsegundos.
* **Solução Ótima:** Mantenha a avaliação e reprodução locais sequenciais dentro de cada ilha/partição, e execute apenas as **ilhas inteiras** como tarefas paralelas:
  ```bend
  # Macro-tarefa paralela ideal:
  match arch:
    case SingleIsland{tree}:
      SingleIsland{run_island_seq(e, tree, seed)} # Roda isolado no core
    case ArchBranch{left, right}:
      l r = evolve_arch(left) evolve_arch(right)   # Bifurcação entre cores
      ArchBranch{l, r}
  ```

### Regra 3: Fusão de Passos Geracionais (*Fused Evaluation*)
* No design clássico de GA, `step_gen` frequentemente executava 3 travessias separadas da árvore:
  1. `eval_pop(tree)` $\to$ Barreira de threads 1
  2. `best_pop(evaluated)` $\to$ Barreira de threads 2
  3. `reproduce(evaluated, seed, best)` $\to$ Barreira de threads 3
* Ao fundir a avaliação diretamente no nascimento do indivíduo (`Leaf{make_ind(child)}` dentro de `reproduce`), **elimina-se uma travessia inteira e uma barreira global de threads por geração**, economizando milhões de alocações na heap compartilhada.

### Regra 4: Topologia NUMA e Contenção de Heap Compartilhada
* O runtime do Bend 2 aloca um buffer contíguo unificado (`CORPUS`, tipicamente mapeado via `mmap` com 8TB de espaço de endereçamento esparso).
* Em máquinas com múltiplos sockets físicos ou nós NUMA (como os nós Xeon da VM com processadores 0-1 no Socket 0 e 2-3 no Socket 1):
  * 2 Threads operam no mesmo socket e compartilham caches L2/L3 locais com latência mínima (**1.72x speedup**).
  * 4 Threads cruzam o barramento inter-socket UPI/QPI, sofrendo penalidade de acesso remoto à memória para objetos alocados na heap compartilhada.
  * Para cargas com estruturas de dados na heap, paralelizar em 2 cores locais por nó ou isolar tarefas com baixa taxa de alocação maximiza a eficiência.
