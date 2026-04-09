/*
 * sisd.c  —  SISD (Scalar) 버전
 *
 * 이 파일은 강의의 표준 SISD 패턴(float 배열 덧셈·곱셈)을 재현한 것입니다.
 *
 * 측정 대상 연산:
 *   C[i] = A[i] * B[i] + C[i]   (FMA-like, float 배열, N = 1<<24 ≒ 16M 원소)
 *   루프를 REPEAT 번 반복하여 측정 시간이 충분히 길도록 함
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define N       (1 << 24)   /* 16,777,216 floats ≒ 64 MB x3 배열 */
#define REPEAT  5           /* 루프 반복 횟수 (짧으면 늘릴 것) */

/* 나노초 단위 시간 */
static double now_ns(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e9 + t.tv_nsec;
}

int main(void) {
    float *A = (float *)malloc(N * sizeof(float));
    float *B = (float *)malloc(N * sizeof(float));
    float *C = (float *)malloc(N * sizeof(float));
    if (!A || !B || !C) { fprintf(stderr, "malloc failed\n"); return 1; }

    /* 초기화 */
    for (int i = 0; i < N; i++) {
        A[i] = (float)(i % 1024) * 0.001f;
        B[i] = (float)(i % 512)  * 0.002f;
        C[i] = 1.0f;
    }

    /* 워밍업 (캐시/분기 예측기 준비) */
    for (int i = 0; i < N; i++)
        C[i] = A[i] * B[i] + C[i];

    /* ---- 측정 시작 ---- */
    double t_start = now_ns();

    for (int r = 0; r < REPEAT; r++) {
        for (int i = 0; i < N; i++) {
            C[i] = A[i] * B[i] + C[i];
        }
    }

    double t_end = now_ns();
    /* ---- 측정 종료 ---- */

    double elapsed_ms = (t_end - t_start) / 1e6;

    /* 결과 출력 (최적화 제거 방지용 체크섬) */
    float checksum = 0.0f;
    for (int i = 0; i < 16; i++) checksum += C[i];

    printf("SISD  N=%d REPEAT=%d  time=%.3f ms  checksum=%.4f\n",
           N, REPEAT, elapsed_ms, checksum);

    free(A); free(B); free(C);
    return 0;
}
