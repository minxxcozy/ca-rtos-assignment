#!/usr/bin/env python3
"""
plot_results.py  —  results/results.csv 를 읽어 그래프 2장 생성

출력:
  results/graph_time.png    — 옵션별 평균 실행시간 (SISD vs SIMD 막대)
  results/graph_speedup.png — 옵션별 speedup 비율
"""

import csv, sys, os, statistics
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np

# ── 경로 ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH   = os.path.join(SCRIPT_DIR, "results", "results.csv")
OUT_DIR    = os.path.join(SCRIPT_DIR, "results")
os.makedirs(OUT_DIR, exist_ok=True)

# ── CSV 읽기 ──────────────────────────────────────────────────────────────────
data: dict[tuple, list[float]] = {}
with open(CSV_PATH) as f:
    for row in csv.DictReader(f):
        try:
            t = float(row['time_ms'])
        except (ValueError, KeyError):
            continue
        if t <= 0:
            continue
        key = (row['tag'], row['target'])
        data.setdefault(key, []).append(t)

# ── 통계 계산 ─────────────────────────────────────────────────────────────────
stats: dict[tuple, dict] = {}
for key, times in data.items():
    if len(times) < 2:
        continue
    stats[key] = {
        'mean':   statistics.mean(times),
        'min':    min(times),
        'max':    max(times),
        'stddev': statistics.stdev(times),
    }

all_tags = sorted({tag for (tag, _) in stats})

sisd_mean = [stats.get((t, 'sisd'), {}).get('mean', 0) for t in all_tags]
simd_mean = [stats.get((t, 'simd'), {}).get('mean', 0) for t in all_tags]
sisd_std  = [stats.get((t, 'sisd'), {}).get('stddev', 0) for t in all_tags]
simd_std  = [stats.get((t, 'simd'), {}).get('stddev', 0) for t in all_tags]
speedups  = [s/d if d > 0 else 0 for s, d in zip(sisd_mean, simd_mean)]

x = np.arange(len(all_tags))
W = 0.38

# ── 그래프 1: 실행시간 막대 ────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(max(12, len(all_tags)*0.85), 6))

bars_s = ax.bar(x - W/2, sisd_mean, W, label='SISD', color='#5b8dd9',
                yerr=sisd_std, capsize=3, error_kw={'linewidth':0.8})
bars_d = ax.bar(x + W/2, simd_mean, W, label='SIMD', color='#e07b54',
                yerr=simd_std, capsize=3, error_kw={'linewidth':0.8})

ax.set_xticks(x)
ax.set_xticklabels(all_tags, rotation=45, ha='right', fontsize=8)
ax.set_ylabel('평균 실행시간 (ms)', fontsize=11)
ax.set_title('SISD vs SIMD — 컴파일 옵션별 평균 실행시간\n(오차 막대: 표준편차, 실제 측정값으로 교체 필요)', fontsize=12)
ax.legend(fontsize=10)
ax.yaxis.set_minor_locator(mticker.AutoMinorLocator())
ax.grid(axis='y', linestyle='--', alpha=0.4)

# 막대 위에 값 표시
for bar in bars_s:
    h = bar.get_height()
    if h > 0:
        ax.text(bar.get_x() + bar.get_width()/2, h*1.01,
                f'{h:.0f}', ha='center', va='bottom', fontsize=6.5, color='#3a5fa0')
for bar in bars_d:
    h = bar.get_height()
    if h > 0:
        ax.text(bar.get_x() + bar.get_width()/2, h*1.01,
                f'{h:.0f}', ha='center', va='bottom', fontsize=6.5, color='#a04020')

plt.tight_layout()
out1 = os.path.join(OUT_DIR, 'graph_time.png')
plt.savefig(out1, dpi=150)
plt.close()
print(f"저장: {out1}")

# ── 그래프 2: Speedup 막대 ────────────────────────────────────────────────────
fig2, ax2 = plt.subplots(figsize=(max(12, len(all_tags)*0.85), 5))

colors = ['#2ecc71' if s > 1.0 else '#e74c3c' for s in speedups]
bars_sp = ax2.bar(x, speedups, 0.6, color=colors, alpha=0.85)

ax2.axhline(1.0, color='black', linewidth=1.0, linestyle='--', label='speedup = 1 (동일)')
ax2.set_xticks(x)
ax2.set_xticklabels(all_tags, rotation=45, ha='right', fontsize=8)
ax2.set_ylabel('Speedup (SISD 시간 / SIMD 시간)', fontsize=11)
ax2.set_title('SISD vs SIMD — Speedup 비율\n(1.0 이상: SIMD가 빠름 / 초록, 미만: SIMD가 느림 / 빨강)', fontsize=12)
ax2.legend(fontsize=9)
ax2.grid(axis='y', linestyle='--', alpha=0.4)

for bar, sp in zip(bars_sp, speedups):
    if sp > 0:
        ax2.text(bar.get_x() + bar.get_width()/2,
                 max(sp + 0.02, 0.05),
                 f'{sp:.2f}x', ha='center', va='bottom', fontsize=7)

plt.tight_layout()
out2 = os.path.join(OUT_DIR, 'graph_speedup.png')
plt.savefig(out2, dpi=150)
plt.close()
print(f"저장: {out2}")

# ── 텍스트 요약 ────────────────────────────────────────────────────────────────
print("\n" + "="*65)
print(f"{'옵션 태그':<35} {'SISD(ms)':>9} {'SIMD(ms)':>9} {'Speedup':>8}")
print("-"*65)
for tag, ss, sd, sp in zip(all_tags, sisd_mean, simd_mean, speedups):
    mark = "★" if sp > 1.5 else ("△" if sp > 1.0 else "▽")
    print(f"{tag:<35} {ss:>9.1f} {sd:>9.1f} {sp:>7.2f}x {mark}")
