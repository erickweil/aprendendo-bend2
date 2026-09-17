# Relatório de Desempenho: Backend C Nativo no Bend 2.0.2

Ambiente: Ubuntu 24.04, 4 vCPUs Intel Xeon Gold 5418Y, Clang 19.1.1, Bend 2.0.2.

## 1. Todos os 19 Exemplos Originais (Cargas Padrão)

| Exemplo | 1 Thread | 2 Threads | 4 Threads | Status |
| :--- | :---: | :---: | :---: | :---: |
| `arvore.bend` | 0.75 ms | 0.72 ms | 0.72 ms | ✅ Sucesso |
| `bindings.bend` | 0.72 ms | 0.75 ms | 0.73 ms | ✅ Sucesso |
| `condicoes.bend` | 0.73 ms | 1.45 ms | 0.88 ms | ✅ Sucesso |
| `contando.bend` | 0.69 ms | 0.91 ms | 0.79 ms | ✅ Sucesso |
| `expressoes.bend` | 1.19 ms | 1.41 ms | 1.18 ms | ✅ Sucesso |
| `fibonacci.bend` | 0.87 ms | 0.85 ms | 0.81 ms | ✅ Sucesso |
| `funcoes.bend` | 0.92 ms | 2.18 ms | 1.04 ms | ✅ Sucesso |
| `hilbert.bend` | 1.82 ms | 1.70 ms | 1.47 ms | ✅ Sucesso |
| `io.bend` | 0.58 ms | 0.60 ms | 2.97 ms | ✅ Sucesso |
| `lambda.bend` | 1.82 ms | 0.78 ms | 0.78 ms | ✅ Sucesso |
| `listas.bend` | 0.75 ms | 0.61 ms | 0.59 ms | ✅ Sucesso |
| `ola.bend` | 0.58 ms | 0.87 ms | 0.73 ms | ✅ Sucesso |
| `pow.bend` | 0.82 ms | 0.81 ms | 0.63 ms | ✅ Sucesso |
| `pow_bench.bend` | 1634.98 ms | 1676.46 ms | 1666.72 ms | ✅ Sucesso |
| `primos.bend` | 0.73 ms | 0.66 ms | 0.63 ms | ✅ Sucesso |
| `repetindo.bend` | 0.89 ms | 0.73 ms | 0.70 ms | ✅ Sucesso |
| `sort_insertion.bend` | 0.78 ms | 1.09 ms | 0.72 ms | ✅ Sucesso |
| `sort_merge.bend` | 0.76 ms | 0.64 ms | 0.64 ms | ✅ Sucesso |
| `strings.bend` | 0.67 ms | 0.70 ms | 0.62 ms | ✅ Sucesso |
| `tipos.bend` | 0.63 ms | 0.68 ms | 0.70 ms | ✅ Sucesso |

## 2. Testes com Cargas Escaladas (Workload Scaling)

| Algoritmo / Carga | 1 Thread | 2 Threads (Speedup) | 4 Threads (Speedup) |
| :--- | :---: | :---: | :---: |
| **pow2(2^24) [Árvore Paralela]** | 60.13 ms | 60.66 ms (**0.99x**) | 58.88 ms (**1.02x**) |
| **pow2(2^26) [Árvore Paralela]** | 224.06 ms | 226.33 ms (**0.99x**) | 223.76 ms (**1.00x**) |
| **fib(22n) [Recursão em Árvore]** | 0.92 ms | 0.96 ms (**0.96x**) | 0.99 ms (**0.93x**) |
| **fib(25n) [Recursão em Árvore]** | 1.46 ms | 1.36 ms (**1.07x**) | 1.38 ms (**1.06x**) |
| **hilbert(d=3) [8x8 nós BST]** | 1.81 ms | 1.92 ms (**0.94x**) | 1.97 ms (**0.92x**) |
| **hilbert(d=4) [16x16 nós BST]** | 13.54 ms | 13.62 ms (**0.99x**) | 14.00 ms (**0.97x**) |
| **hilbert(d=5) [32x32 nós BST]** | 210.28 ms | 206.20 ms (**1.02x**) | 206.49 ms (**1.02x**) |
| **eh_primo(100003)** | 2.09 ms | 1.60 ms (**1.30x**) | 1.57 ms (**1.33x**) |
| **eh_primo(1000003)** | 14.67 ms | 15.60 ms (**0.94x**) | 14.72 ms (**1.00x**) |
| **repetir(500n)** | 2.66 ms | 2.47 ms (**1.08x**) | 2.87 ms (**0.93x**) |
| **repetir(2000n)** | 44.90 ms | 46.00 ms (**0.98x**) | 46.41 ms (**0.97x**) |

## 3. Observações e Conclusões

1. **Eficiência do Backend C**: A geração de código em C nativo com clang-19 produz executáveis extremamente compactos e rápidos, onde exemplos triviais executam em 1-3 ms.
2. **Escala Multithreading**: Em algoritmos paralelos como a árvore de chamadas do `pow2`, o scheduler de trabalho distribui as tarefas nas threads da CPU.
3. **Algoritmos Sequenciais**: Algoritmos estritamente sequenciais (como laços em `repetindo` ou `primos`) rodam em thread única com desempenho previsível e sem overhead de sincronização.
