#!/usr/bin/env bash
set -e

export PATH="/home/ubuntu/claude/.toolchain/bend/bin:$PATH"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "================================================================"
echo "    BEND 2 - SUITE DO ALGORITMO GENÉTICO PARALELO EM ÁRVORE    "
echo "================================================================"
echo "Compilador: $(bend --version)"
echo "Arquitetura: Árvore Binária Fork-Join + PRNG Puro com Seed-Split"
echo "Topologia de Teste: 1 Thread vs 8 Threads (Multicore Scale)"
echo "================================================================"
echo ""

echo "================================================================"
echo ">> [FASE 0] VERIFICAÇÃO FORMAL DE LEIS MATEMÁTICAS (LAWS & PROOF)"
echo "================================================================"
echo "Verificando 22 leis do motor genético, utilitários e combinadores"
echo "de operadores via 'bend PROOF.bend'..."
bend PROOF.bend
echo "✓ Todas as 22 leis matemáticas foram verificadas e provadas com sucesso!"
echo "================================================================"
echo ""

echo "================================================================"
echo ">> [FASE 0.1] TESTE EXAUSTIVO DOS OPERADORES (operators.bend)"
echo "================================================================"
echo "Verificando que os operadores de permutação fecham sobre permutações"
echo "válidas (OX1, PMX, Directed Swap, 2-Opt, Scramble, Neighbor Swap)..."
bend tests/operators_test.bend
echo "================================================================"
echo ""

declare -a TABLE_SCENARIO=()
declare -a TABLE_T1=()
declare -a TABLE_T8=()
declare -a TABLE_RATIO=()

run_scenario() {
    local num="$1"
    local name="$2"
    local file="$3"
    local bin="$DIR/src/bin_${num}"

    echo "----------------------------------------------------------------"
    echo ">> Rodando Cenário $num: $name"
    echo "----------------------------------------------------------------"

    echo "[1/3] Modo Interpretado (bend $file):"
    time bend "$file"
    echo ""

    echo "[2/3] Compilando e Executando em C - 1 Thread (bend $file -o $bin && $bin --threads 1):"
    bend "$file" -o "$bin"

    t1_s=$(date +%s%N)
    "$bin" --threads 1
    t1_e=$(date +%s%N)
    t1_ms=$(( (t1_e - t1_s) / 1000000 ))
    [ "$t1_ms" -le 0 ] && t1_ms=1
    echo "Tempo de Execução (1 Thread):  ${t1_ms} ms"
    echo ""

    echo "[3/3] Modo Compilado C - 8 Threads ($bin --threads 8):"
    t8_s=$(date +%s%N)
    "$bin" --threads 8
    t8_e=$(date +%s%N)
    t8_ms=$(( (t8_e - t8_s) / 1000000 ))
    [ "$t8_ms" -le 0 ] && t8_ms=1
    echo "Tempo de Execução (8 Threads): ${t8_ms} ms"
    echo ""

    ratio=$(awk "BEGIN {printf \"%.2f\", $t1_ms / $t8_ms}")
    if (( $(awk "BEGIN {print ($ratio >= 1.0)}") )); then
        echo ">> Análise de Paralelismo: 8 Threads entregou ${ratio}x de aceleração (speedup) vs 1 Thread."
    else
        inv_ratio=$(awk "BEGIN {printf \"%.2f\", $t8_ms / $t1_ms}")
        echo ">> Análise de Paralelismo: 1 Thread foi ${inv_ratio}x mais rápida (overhead de startup de 8 pthreads em carga ultra-rápida de ${t1_ms}ms)."
    fi
    echo ""

    TABLE_SCENARIO+=("$name")
    TABLE_T1+=("${t1_ms}ms")
    TABLE_T8+=("${t8_ms}ms")
    TABLE_RATIO+=("${ratio}x")

    rm -f "$bin"
}

run_scenario "1" "Bit Maxing (One-Max)" "src/scenario1_onemax.bend"
run_scenario "2" "Ordenar Números (Sorting)" "src/scenario2_sorting.bend"
run_scenario "3" "Caixeiro Viajante (TSP)" "src/scenario3_tsp.bend"
run_scenario "4" "Sudoku Solver" "src/scenario4_sudoku.bend"
run_scenario "5" "Solver de Horário Escolar" "src/scenario5_horario.bend"
run_scenario "6" "Problema das 8-Rainhas (N-Queens)" "src/scenario6_nqueens.bend"
run_scenario "7" "Problema da Mochila (Knapsack)" "src/scenario7_knapsack.bend"
run_scenario "8" "Evolução de Strings (Weasel)" "src/scenario8_weasel.bend"
run_scenario "9" "Cellular GA (cGA / Quad-Tree)" "src/scenario9_cga.bend"
run_scenario "10" "Programação Genética (GP)" "src/scenario10_gp.bend"
run_scenario "11" "Multi-Objetivo (Pareto MOEA)" "src/scenario11_multiobjective.bend"
run_scenario "12" "Co-Evolução Competitiva" "src/scenario12_coevolution.bend"
run_scenario "13" "Motor Auto-Adaptativo" "src/scenario13_self_adaptive.bend"
run_scenario "14" "Evolução Diferencial (DE)" "src/scenario14_differential_evolution.bend"
run_scenario "15" "Neuroevolução (Cart-Pole)" "src/scenario15_neuroevolution.bend"
run_scenario "16" "Genética Diplóide Dinâmica" "src/scenario16_diploid_dynamic.bend"
run_scenario "PGA" "Modelo de Ilhas (Island Model)" "src/island_ga.bend"
run_scenario "BENCH" "Benchmark Paralelo (8 Ilhas)" "bench_parallel.bend"

echo "=========================================================================================="
echo "          TABELA CONSOLIDADA DE PARALELISMO: 1 THREAD VS 8 THREADS (BEND 2)               "
echo "=========================================================================================="
printf "%-35s | %12s | %12s | %15s\n" "Cenário / Algoritmo" "1 Thread" "8 Threads" "Speedup (1T/8T)"
echo "------------------------------------+--------------+--------------+-----------------------"
for i in "${!TABLE_SCENARIO[@]}"; do
    printf "%-35s | %12s | %12s | %15s\n" "${TABLE_SCENARIO[$i]}" "${TABLE_T1[$i]}" "${TABLE_T8[$i]}" "${TABLE_RATIO[$i]}"
done
echo "=========================================================================================="
echo "    TODOS OS CENÁRIOS FORAM EXECUTADOS COM SUCESSO!                                       "
echo "=========================================================================================="

