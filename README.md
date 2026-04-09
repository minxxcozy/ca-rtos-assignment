# ✏️ SISD vs SIMD 벤치마크 — 사용 가이드

## 🗂️ 디렉토리 구조

```
simd_bench/
├── src/
│   ├── sisd.c          
│   └── simd.c          
├── bin/                ← 빌드된 바이너리 (자동 생성)
├── results/            ← CSV + 그래프 출력 (자동 생성)
├── logs/               ← 빌드/실행 로그 (자동 생성)
├── bench.sh            ← 메인 자동화 스크립트
└── plot_results.py     ← 결과 시각화 스크립트
```

## 🛠️ 실행 전 준비

```bash
# 1. 필요 패키지 확인
sudo apt update
sudo apt install -y gcc clang bc python3 python3-matplotlib

# 2. CPU 기능 확인 (AVX2 지원 여부)
grep -o 'avx2\|sse4_2\|fma' /proc/cpuinfo | sort -u

# 3. 스크립트 권한 부여
chmod +x bench.sh
```

## 🏃 실행

```bash
# 전체 빌드 + 측정 (약 3~10분 소요)
./bench.sh

# 그래프 생성
python3 plot_results.py
```

## ❗ 파일 구조가 다를 경우 조정 방법

### 1️⃣ simd.c가 SSE2/SSE4.2 기반인 경우
`bench.sh` 내 `SIMD_FLAGS` 변수를 수정:
```bash
SIMD_FLAGS="-msse4.2"    # SSE4.2 기반
SIMD_FLAGS="-mavx"       # AVX (128/256-bit, FMA 없음)
SIMD_FLAGS="-mavx2 -mfma" # AVX2 + FMA (기본값)
```

### 2️⃣ 실행시간이 너무 짧은 경우 (10ms 미만)
sisd.c / simd.c 상단의 `REPEAT` 값을 늘리세요:
```c
#define REPEAT  50   // 5 → 50으로 증가
```

### 3️⃣ N(배열 크기)을 강의 파일에 맞게 조정
```c
#define N  (1 << 20)   // 1M (소규모)
#define N  (1 << 24)   // 16M (기본값)
#define N  (1 << 26)   // 64M (대규모)
```

## 📊 결과 해석 체크포인트

1. `gcc_O0` 에서 SISD와 SIMD의 시간 차이 → intrinsic의 raw 효과
2. `gcc_O3_novec` vs `gcc_O3` → 컴파일러 auto-vectorization의 영향
3. `gcc_O3_native` vs `clang_O3_native` → 컴파일러 간 차이
4. speedup이 이론값(AVX2=8x, SSE=4x)보다 낮은 이유 → 메모리 병목, 설정 오버헤드
5. `gcc_Ofast` 의 checksum이 다른 경우 → 부동소수점 정밀도 차이 주의
