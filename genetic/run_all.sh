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
echo "================================================================"
echo ""

run_scenario() {
    local num="$1"
    local name="$2"
    local file="$3"
    local bin="$DIR/src/bin_${num}"

    echo "----------------------------------------------------------------"
    echo ">> Rodando Cenário $num: $name"
    echo "----------------------------------------------------------------"

    echo "[1/2] Modo Interpretado (bend $file):"
    time bend "$file"
    echo ""

    echo "[2/2] Modo Compilado C (bend $file -o $bin):"
    bend "$file" -o "$bin"
    time "$bin"
    rm -f "$bin"
    echo ""
}

run_scenario "1" "Bit Maxing (One-Max)" "src/scenario1_onemax.bend"
run_scenario "2" "Ordenar Números (Number Sorting)" "src/scenario2_sorting.bend"
run_scenario "3" "Caixeiro Viajante (TSP)" "src/scenario3_tsp.bend"
run_scenario "4" "Sudoku Solver" "src/scenario4_sudoku.bend"
run_scenario "5" "Solver de Horário Escolar" "src/scenario5_horario.bend"
run_scenario "6" "Problema das 8-Rainhas (N-Queens)" "src/scenario6_nqueens.bend"
run_scenario "7" "Problema da Mochila (0/1 Knapsack)" "src/scenario7_knapsack.bend"
run_scenario "8" "Evolução de Strings (Dawkins Weasel)" "src/scenario8_weasel.bend"
run_scenario "9" "Cellular Genetic Algorithm (cGA / Quad-Tree)" "src/scenario9_cga.bend"
run_scenario "PGA" "Modelo de Ilhas Paralelas (Island Model)" "src/island_ga.bend"

echo "================================================================"
echo "    TODOS OS CENÁRIOS FORAM EXECUTADOS COM SUCESSO!             "
echo "================================================================"
