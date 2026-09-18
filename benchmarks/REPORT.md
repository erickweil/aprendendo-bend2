# Relatório de Desempenho: Backend C Nativo no Bend 2

Ambiente: Ubuntu 24.04, 4 vCPUs Intel Xeon Gold 5418Y, Clang 19.1.1, Bend 2.

## 1. Todos os 19 Exemplos Originais (Cargas Padrão)

| Exemplo | 1 Thread | 2 Threads | 4 Threads | Status |
| :--- | :---: | :---: | :---: | :---: |
| `arvore.bend` | 0.93 ms | 0.89 ms | 0.86 ms | ✅ Sucesso |
| `bindings.bend` | 0.98 ms | 0.90 ms | 0.84 ms | ✅ Sucesso |
| `condicoes.bend` | 0.98 ms | 0.91 ms | 0.84 ms | ✅ Sucesso |
| `contando.bend` | 0.92 ms | 0.85 ms | 0.81 ms | ✅ Sucesso |
| `expressoes.bend` | 1.48 ms | 1.42 ms | 1.37 ms | ✅ Sucesso |
| `fibonacci.bend` | 0.75 ms | 0.74 ms | 0.74 ms | ✅ Sucesso |
| `funcoes.bend` | 0.90 ms | 0.82 ms | 0.75 ms | ✅ Sucesso |
| `hilbert.bend` | 1.75 ms | 1.80 ms | 1.89 ms | ✅ Sucesso |
| `io.bend` | 0.94 ms | 0.96 ms | 1.00 ms | ✅ Sucesso |
| `lambda.bend` | 1.02 ms | 0.98 ms | 0.93 ms | ✅ Sucesso |
| `listas.bend` | 1.13 ms | 0.98 ms | 0.90 ms | ✅ Sucesso |
| `ola.bend` | 1.13 ms | 1.05 ms | 0.97 ms | ✅ Sucesso |
| `pow.bend` | 1.02 ms | 1.20 ms | 1.58 ms | ✅ Sucesso |
| `primos.bend` | 1.03 ms | 1.00 ms | 0.97 ms | ✅ Sucesso |
| `repetindo.bend` | 1.08 ms | 1.05 ms | 1.04 ms | ✅ Sucesso |
| `sort_insertion.bend` | 0.96 ms | 0.99 ms | 1.02 ms | ✅ Sucesso |
| `sort_merge.bend` | 1.13 ms | 1.25 ms | 1.46 ms | ✅ Sucesso |
| `strings.bend` | 1.14 ms | 1.08 ms | 1.02 ms | ✅ Sucesso |
| `tipos.bend` | 0.97 ms | 0.94 ms | 0.90 ms | ✅ Sucesso |

## 2. Testes com Cargas Escaladas (Workload Scaling)

| Algoritmo / Carga | 1 Thread | 2 Threads (Speedup) | 4 Threads (Speedup) |
| :--- | :---: | :---: | :---: |
| **pow2(2^24) [Árvore Paralela]** | 64.75 ms | 36.49 ms (**1.77x**) | 20.80 ms (**3.11x**) |
| **pow2(2^26) [Árvore Paralela]** | 264.00 ms | 139.38 ms (**1.89x**) | 82.31 ms (**3.21x**) |
| **fib(22n) [Recursão em Árvore]** | 1.19 ms | 1.09 ms (**1.09x**) | 1.10 ms (**1.08x**) |
| **fib(25n) [Recursão em Árvore]** | 1.53 ms | 1.47 ms (**1.04x**) | 1.29 ms (**1.19x**) |
| **hilbert(d=3) [8x8 nós BST]** | 2.00 ms | 2.00 ms (**1.00x**) | 1.92 ms (**1.04x**) |
| **hilbert(d=4) [16x16 nós BST]** | 17.57 ms | 16.93 ms (**1.04x**) | 17.41 ms (**1.01x**) |
| **hilbert(d=5) [32x32 nós BST]** | 261.87 ms | 219.92 ms (**1.19x**) | 261.95 ms (**1.00x**) |
| **eh_primo(100003)** | 1.91 ms | 1.69 ms (**1.13x**) | 1.89 ms (**1.01x**) |
| **eh_primo(1000003)** | 15.74 ms | 15.71 ms (**1.00x**) | 15.54 ms (**1.01x**) |
| **repetir(500n)** | 3.26 ms | 3.30 ms (**0.99x**) | 3.31 ms (**0.99x**) |
| **repetir(2000n)** | 57.83 ms | 58.75 ms (**0.98x**) | 57.65 ms (**1.00x**) |

## 3. Observações e Conclusões

1. **Eficiência do Backend C**: A geração de código em C nativo com clang-19 produz executáveis extremamente compactos e rápidos, onde exemplos triviais executam em ~1 ms.
2. **Escala Multithreading Real em Árvores Fork-Join**: Em algoritmos puramente paralelos baseados em árvore com granularidade suficiente (como `pow2(2^24)` e `pow2(2^26)`), o scheduler de threads C distribui as tarefas de forma altamente eficiente, atingindo **3.21x de speedup em 4 threads**.
3. **Algoritmos Sequenciais**: Algoritmos estritamente sequenciais (como laços em `repetindo` ou testes de divisão em `primos`) rodam de forma determinística sem overhead prejudicial de sincronização.
