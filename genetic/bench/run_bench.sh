#!/usr/bin/env bash
# Harness de benchmark do motor genético.
# Uso: ./bench/run_bench.sh [tag]   (tag rotula a linha de saída)
set -e
export PATH="/home/ubuntu/claude/.toolchain/bend/bin:$PATH"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"
TAG="${1:-atual}"
REPS=7

# mínimo, não mediana: esta VM tem 4 vCPUs compartilhadas e o ruído é
# sempre aditivo, então o mínimo é o estimador estável do custo real.
best() { printf '%s\n' "$@" | sort -n | head -1; }

run_one() {
    local bin="$1" threads="$2"
    local times=()
    for _ in $(seq $REPS); do
        local s=$(date +%s%N)
        "$bin" --threads "$threads" >/dev/null
        local e=$(date +%s%N)
        times+=( $(( (e - s) / 1000000 )) )
    done
    best "${times[@]}"
}

printf "%-14s %-10s %8s %8s %8s %10s\n" "BENCH" "TAG" "1T" "2T" "4T" "SPEEDUP4"
for b in bench_perm bench_bits bench_gp; do
    bin="/tmp/bench_${b}_$$"
    bend "bench/$b.bend" -o "$bin" >/dev/null 2>&1
    t1=$(run_one "$bin" 1)
    t2=$(run_one "$bin" 2)
    t4=$(run_one "$bin" 4)
    sp=$(awk "BEGIN{printf \"%.2fx\", $t1/$t4}")
    printf "%-14s %-10s %7sms %7sms %7sms %10s\n" "$b" "$TAG" "$t1" "$t2" "$t4" "$sp"
    rm -f "$bin"
done
