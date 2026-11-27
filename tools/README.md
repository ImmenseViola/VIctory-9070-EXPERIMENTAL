# Local harness scripts

These are the Windows PowerShell scripts used to launch and measure the A/B
runs recorded in [EXPERIMENT_LOG.md](../EXPERIMENT_LOG.md). Their default
paths point at this machine's permanent `C:\mygame\victory-work` workspace:
the experimental repo, warmed cache, and future logs live there. Edit them
for your own setup.

| Script | Purpose |
|---|---|
| `start-play-session.ps1` | Launch a tagged game session with the tuned environment, optional binary, cache, console/upscaler, and `-Extra` switches. |
| `harness-env.ps1` | The single source of the tuned environment variables, shared by the launcher and the cache probe; do not duplicate its table. |
| `cache-fingerprint.ps1` | Run `victory warm` with the exact harness environment. Default (`-Limit 0`) only prints the current pipeline fingerprint and counts; `-Warm` tops up early pipelines for that fingerprint. |
| `monitor-active.ps1` | Passive screen/motion/memory/FPS sampler; writes `<tag>-monitor.csv`. |
| `summarize-ab.ps1` | Group `A/B phase` log lines by switch bits and print mean/median/p90/draws; dense phases only (default `>= 3000` draws). |
| `stop-after-clean-ab.ps1` | Stop a run at a chosen phase or private-memory limit; aborts if dense gameplay has not appeared within 5 minutes of process start, otherwise refuses to kill while shader translation or host pipeline creation is active. |
| `measure-perf.ps1` | 60 s log-window frame-time/copy/texture sampler; writes `<tag>-perf.csv`. |
| `ocr-shot.ps1` | OCR the overlay from a captured frame, for passive checks without input. |

Typical A/B launch:

```powershell
& .\tools\start-play-session.ps1 -Tag texview-ab2 `
  -Binary ..\target-exp\diag\victory.exe `
  -Console series-x -Upscaler 6 `
  -Cache 'C:\mygame\victory-work\victory-9070-cache-v3-fixed' `
  -Extra @{
    VICTORY_CARD_BUFFERS_MIN_MB='1'
    VICTORY_LATE_WAIT='3'
    VICTORY_AB='20,VICTORY_TEX_VIEW_CACHE'
    VICTORY_KEYS='2:Enter,5:Enter,8:Enter,11:Enter,20:Enter,75:Enter,78:Enter'
  }
```

Start the monitor and watcher in the background, then let the watcher stop the
run. Do not send manual input during an automated A/B. Use the Enter-only
schedule after world entry (as above); movement/camera keys make phases see
different scenes and confound the result.

For a stage breakdown without changing any switch under test, use the same
launch with `VICTORY_COPY_STAGES='1'` in `-Extra` and no `VICTORY_AB`. The
diagnostics build then prints a `copy recording stages per frame` line beside
the frame line, and a copy-back wait/fetch/book line with that same interval's
total.
`VICTORY_REFRESH_CHECK='1'` adds only the verification stage's time when that
correctness probe is wanted; leave it off for a representative timing sample.
The launcher's default binary is `target\diag\victory.exe`; pass `-Binary` only
to override it. A stale `target-exp\diag` binary once produced a stage run
with no breakdown lines, so check the binary before trusting a log.
