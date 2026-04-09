/*
 * simd.c  —  SIMD (AVX2 intrinsic) 버전
 *
 * 실제 강의 제공 파일이 있다면 이 파일을 덮어쓰세요.
 * 이 파일은 sisd.c와 완전히 동일한 연산을 AVX2 intrinsic으로 구현한 것입니다.
 *
 * 측정 대상 연산:
 *   C[i] = A[i] * B[i] + C[i]   (float 배열, N = 1<<24, AVX2: 8 floats/cycle)
 *
 * 컴파일 시 반드시 -mavx2 (또는 -march=native) 필요
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <immintrin.h>   /* AVX2 intrinsic 헤더 */

#define N       (1 << 24)
#define REPEAT  5

static double now_ns(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e9 + t.tv_nsec;
}

int main(void) {
    /* 32바이트 정렬 할당 (AVX2는 256-bit = 32바이트 정렬 권장) */
    float *A = (float *)aligned_alloc(32, N * sizeof(float));
    float *B = (float *)aligned_alloc(32, N * sizeof(float));
    float *C = (float *)aligned_alloc(32, N * sizeof(float));
    if (!A || !B || !C) { fprintf(stderr, "aligned_alloc failed\n"); return 1; }

    /* 초기화 (sisd.c와 동일) */
    for (int i = 0; i < N; i++) {
        A[i] = (float)(i % 1024) * 0.001f;
        B[i] = (float)(i % 512)  * 0.002f;
        C[i] = 1.0f;
    }

    /* 워밍업 */
    {
        int vec_n = N / 8;
        for (int i = 0; i < vec_n; i++) {
            __m256 va = _mm256_load_ps(&A[i*8]);
            __m256 vb = _mm256_load_ps(&B[i*8]);
            __m256 vc = _mm256_load_ps(&C[i*8]);
            vc = _mm256_fmadd_ps(va, vb, vc);   /* FMA: va*vb + vc */
            _mm256_store_ps(&C[i*8], vc);
        }
    }

    /* ---- 측정 시작 ---- */
    double t_start = now_ns();

    int vec_n = N / 8;  /* AVX2: 256-bit = 8 x float */
    for (int r = 0; r < REPEAT; r++) {
        for (int i = 0; i < vec_n; i++) {
            __m256 va = _mm256_load_ps(&A[i*8]);
            __m256 vb = _mm256_load_ps(&B[i*8]);
            __m256 vc = _mm256_load_ps(&C[i*8]);
            vc = _mm256_fmadd_ps(va, vb, vc);
            _mm256_store_ps(&C[i*8], vc);
        }
    }

    double t_end = now_ns();
    /* ---- 측정 종료 ---- */

    double elapsed_ms = (t_end - t_start) / 1e6;

    float checksum = 0.0f;
    for (int i = 0; i < 16; i++) checksum += C[i];

    printf("SIMD  N=%d REPEAT=%d  time=%.3f ms  checksum=%.4f\n",
           N, REPEAT, elapsed_ms, checksum);

    free(A); free(B); free(C);
    return 0;
}
