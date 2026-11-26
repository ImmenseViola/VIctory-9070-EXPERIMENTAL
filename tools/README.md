# Local harness scripts

These are the Windows PowerShell scripts used to launch and measure the A/B
runs recorded in [EXPERIMENT_LOG.md](../EXPERIMENT_LOG.md). They are copied
from the tuning harness as-is, so the default paths point at this machine's
`C:\Users\Admin\AppData\Local\Temp\opencode` workspace. Edit them for your own
setup.

| Script | Purpose |
|---|---|
| `start-play-session.ps1` | Launch a tagged game session with the tuned environment, optional binary, cache, console/upscaler, and `-Extra` switches. |
| `monitor-active.ps1` | Passive screen/motion/memory/FPS sampler; writes `<tag>-monitor.csv`. |
| `summarize-ab.ps1` | Group `A/B phase` log lines by switch bits and print mean/median/p90/draws. |
| `stop-after-clean-ab.ps1` | Stop a run at a chosen phase or private-memory limit; refuses to kill while shader translation or host pipeline creation is active. |
| `measure-perf.ps1` | 60 s log-window frame-time/copy/texture sampler; writes `<tag>-perf.csv`. |
| `ocr-shot.ps1` | OCR the overlay from a captured frame, for passive checks without input. |

Typical A/B launch:

```powershell
& .\tools\start-play-session.ps1 -Tag texview-ab2 `
  -Binary ..\target-exp\diag\victory.exe `
  -Console series-x -Upscaler 6 `
  -Cache 'C:\Users\Admin\AppData\Local\Temp\opencode\victory-7900-clean-cache-1' `
  -Extra @{
    VICTORY_CARD_BUFFERS_MIN_MB='1'
    VICTORY_LATE_WAIT='3'
    VICTORY_AB='20,VICTORY_TEX_VIEW_CACHE'
    VICTORY_KEYS='2:Enter,5:Enter,8:Enter,11:Enter,75:Enter,78:Enter'
  }
```

Start the monitor and watcher in the background, then let the watcher stop the
run. Do not send manual input during an automated A/B.
