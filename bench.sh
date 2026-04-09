#!/usr/bin/env bash
# =============================================================================
# bench.sh  —  SISD vs SIMD 전체 자동 빌드 + 측정 + CSV 저장
#
# 사용법:
#   chmod +x bench.sh
#   ./bench.sh
#
# 출력:
#   results/results.csv   — 전체 측정 결과
#   logs/build.log        — 빌드 에러 로그
#   logs/run.log          — 실행 에러 로그
# =============================================================================

set -euo pipefail

# ── 경로 설정 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
BIN_DIR="$SCRIPT_DIR/bin"
RES_DIR="$SCRIPT_DIR/results"
LOG_DIR="$SCRIPT_DIR/logs"

mkdir -p "$BIN_DIR" "$RES_DIR" "$LOG_DIR"

RESULT_CSV="$RES_DIR/results.csv"
BUILD_LOG="$LOG_DIR/build.log"
RUN_LOG="$LOG_DIR/run.log"

# ── 측정 설정 ─────────────────────────────────────────────────────────────────
RUNS=10          # 각 바이너리를 몇 번 반복 실행할지
WARMUP=1         # 측정 전 워밍업 실행 횟수 (결과 버림)

# ── 컬러 출력 ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERR]${NC}   $*"; }

# ── 컴파일러 존재 여부 확인 ───────────────────────────────────────────────────
check_compiler() {
    local cc="$1"
    if ! command -v "$cc" &>/dev/null; then
        warn "$cc 를 찾을 수 없습니다. 해당 옵션은 건너뜁니다."
        return 1
    fi
    return 0
}

# ── CPU가 AVX2를 지원하는지 확인 ──────────────────────────────────────────────
if ! grep -q avx2 /proc/cpuinfo; then
    warn "이 CPU는 AVX2를 지원하지 않습니다."
    warn "simd.c의 _mm256 intrinsic이 실패할 수 있습니다."
    warn "SSE4.2용 simd.c로 교체하거나 -msse4.2 옵션을 사용하세요."
fi

# =============================================================================
# 컴파일 옵션 테이블 정의
#
# 형식: "컴파일러|옵션_태그|추가_플래그"
# - SIMD 관련 기본 플래그(-mavx2 -mfma)는 simd.c에만 자동 추가됨
# - sisd.c에는 순수 스칼라 관점을 보기 위해 기본적으로 추가 안 함
#   (단, -march=native 포함 케이스는 둘 다 적용)
# =============================================================================
declare -a OPTION_SETS=(
    # ── GCC 기본 최적화 단계 ─────────────────────────────────────────
    "gcc|gcc_O0|                    -O0"
    "gcc|gcc_O1|                    -O1"
    "gcc|gcc_O2|                    -O2"
    "gcc|gcc_O3|                    -O3"
    "gcc|gcc_Ofast|                 -Ofast"

    # ── march=native (현재 CPU 최적화) ──────────────────────────────
    "gcc|gcc_O2_native|             -O2 -march=native -mtune=native"
    "gcc|gcc_O3_native|             -O3 -march=native -mtune=native"
    "gcc|gcc_Ofast_native|          -Ofast -march=native -mtune=native"

    # ── 루프 언롤링 ──────────────────────────────────────────────────
    "gcc|gcc_O2_unroll|             -O2 -funroll-loops"
    "gcc|gcc_O3_unroll|             -O3 -funroll-loops"
    "gcc|gcc_O3_unroll_native|      -O3 -funroll-loops -march=native -mtune=native"

    # ── 벡터화 명시 제어 ─────────────────────────────────────────────
    "gcc|gcc_O3_vec|                -O3 -ftree-vectorize"
    "gcc|gcc_O3_novec|              -O3 -fno-tree-vectorize"
    "gcc|gcc_O2_treevec|            -O2 -ftree-vectorize -march=native"

    # ── Ofast + 언롤 복합 ────────────────────────────────────────────
    "gcc|gcc_Ofast_unroll_native|   -Ofast -funroll-loops -march=native -mtune=native"

    # ── CLANG ────────────────────────────────────────────────────────
    "clang|clang_O0|                -O0"
    "clang|clang_O1|                -O1"
    "clang|clang_O2|                -O2"
    "clang|clang_O3|                -O3"
    "clang|clang_Ofast|             -Ofast"
    "clang|clang_O3_native|         -O3 -march=native -mtune=native"
    "clang|clang_Ofast_native|      -Ofast -march=native -mtune=native"
    "clang|clang_O3_unroll_native|  -O3 -funroll-loops -march=native -mtune=native"
)

# SIMD 필수 플래그 (simd.c 컴파일 시 항상 추가)
SIMD_FLAGS="-mavx2 -mfma"

# =============================================================================
# CSV 헤더 작성
# =============================================================================
echo "compiler,tag,flags,target,run,time_ms" > "$RESULT_CSV"
log "결과 파일: $RESULT_CSV"
log "빌드 로그: $BUILD_LOG"
echo "" > "$BUILD_LOG"
echo "" > "$RUN_LOG"

# =============================================================================
# 빌드 + 실행 함수
# =============================================================================
build_and_run() {
    local compiler="$1"
    local tag="$2"
    local flags="$3"
    local target="$4"   # sisd 또는 simd
    local src="$SRC_DIR/${target}.c"
    local bin="$BIN_DIR/${target}_${tag}"

    # simd.c에는 반드시 SIMD 플래그 추가
    local all_flags="$flags"
    if [[ "$target" == "simd" ]]; then
        all_flags="$flags $SIMD_FLAGS"
    fi

    # 빌드
    if ! $compiler $all_flags -o "$bin" "$src" -lm >> "$BUILD_LOG" 2>&1; then
        err "빌드 실패: $compiler $all_flags $src"
        echo "BUILD_FAIL,$tag,$flags,$target,-1,-1" >> "$RESULT_CSV"
        return 1
    fi

    # 워밍업 실행 (결과 버림)
    for ((w=0; w<WARMUP; w++)); do
        "$bin" > /dev/null 2>> "$RUN_LOG" || true
    done

    # 본 측정
    local run_ok=0
    for ((r=1; r<=RUNS; r++)); do
        # /usr/bin/time -f "%e" 으로 elapsed 초 추출 (Linux GNU time)
        local t_sec
        t_sec=$( { /usr/bin/time -f "%e" "$bin" > /dev/null; } 2>&1 ) || {
            err "실행 실패: $bin (run $r)"
            echo "$compiler,$tag,\"$flags\",$target,$r,-1" >> "$RESULT_CSV"
            echo "RUN_FAIL: $bin run=$r" >> "$RUN_LOG"
            continue
        }
        local t_ms
        t_ms=$(echo "$t_sec * 1000" | bc -l | xargs printf "%.3f")
        echo "$compiler,$tag,\"$flags\",$target,$r,$t_ms" >> "$RESULT_CSV"
        run_ok=$((run_ok+1))
    done

    if [[ $run_ok -eq $RUNS ]]; then
        ok "$target | $tag | ${RUNS}회 완료"
    else
        warn "$target | $tag | $run_ok/${RUNS}회 성공"
    fi
}

# =============================================================================
# 메인 루프
# =============================================================================
echo ""
echo -e "${BOLD}=== SISD vs SIMD 벤치마크 시작 ===${NC}"
echo -e "옵션 조합 수: ${#OPTION_SETS[@]}  |  타깃: sisd, simd  |  각 ${RUNS}회 반복"
echo ""

total=${#OPTION_SETS[@]}
idx=0

for entry in "${OPTION_SETS[@]}"; do
    IFS='|' read -r compiler tag flags <<< "$entry"
    flags=$(echo "$flags" | xargs)   # 앞뒤 공백 제거
    idx=$((idx+1))

    echo -e "${YELLOW}[${idx}/${total}]${NC} $compiler | $tag | $flags"

    # 컴파일러 없으면 건너뜀
    check_compiler "$compiler" || continue

    build_and_run "$compiler" "$tag" "$flags" "sisd"
    build_and_run "$compiler" "$tag" "$flags" "simd"
    echo ""
done

# =============================================================================
# 간이 통계 출력 (Python3 있을 경우)
# =============================================================================
echo ""
echo -e "${BOLD}=== 측정 완료 — 간이 통계 ===${NC}"

if command -v python3 &>/dev/null; then
python3 - "$RESULT_CSV" <<'PYEOF'
import sys, csv, statistics

path = sys.argv[1]
data = {}   # (tag, target) -> [time_ms, ...]

with open(path) as f:
    for row in csv.DictReader(f):
        try:
            t = float(row['time_ms'])
        except ValueError:
            continue
        if t < 0:
            continue
        key = (row['tag'], row['target'])
        data.setdefault(key, []).append(t)

print(f"\n{'tag':<35} {'target':<6} {'mean':>8} {'min':>8} {'max':>8} {'stddev':>8}")
print("-" * 75)

speedups = {}
for (tag, tgt), times in sorted(data.items()):
    if len(times) < 2:
        continue
    mn  = statistics.mean(times)
    mi  = min(times)
    mx  = max(times)
    sd  = statistics.stdev(times)
    print(f"{tag:<35} {tgt:<6} {mn:>8.1f} {mi:>8.1f} {mx:>8.1f} {sd:>8.2f}")
    speedups[(tag, tgt)] = mn

print("\n--- Speedup (SISD / SIMD, 값 > 1 이면 SIMD가 빠름) ---")
all_tags = sorted({tag for (tag, _) in speedups})
for tag in all_tags:
    s = speedups.get((tag, 'sisd'))
    d = speedups.get((tag, 'simd'))
    if s and d and d > 0:
        ratio = s / d
        mark = "★" if ratio > 1.5 else ("△" if ratio > 1.0 else "▽")
        print(f"  {tag:<35} {ratio:>6.2f}x  {mark}")
PYEOF
else
    warn "python3 없음 — 통계 생략. results/results.csv 를 직접 확인하세요."
fi

echo ""
log "전체 결과 저장 위치: $RESULT_CSV"
