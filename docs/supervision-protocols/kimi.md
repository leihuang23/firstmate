Mode: Kimi background-notify supervision.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
2. Source `__FM_X_MODE_ENV__` first when X mode is active.
3. Arm with Kimi's tracked background tool, as its own call:

   `run_terminal_command` with `background: true` on:
   `[ -f __FM_X_MODE_ENV_SH__ ] && . __FM_X_MODE_ENV_SH__; exec bin/fm-watch-arm.sh`

4. Trust only the arm's one-line status.
5. `watcher: started ...` or `watcher: attached ...` means a live cycle exists.
   On attach, the background task stays live until that existing cycle ends; it does not exit immediately.
6. `watcher: FAILED ...` means supervision is down; fix and re-arm.
7. After a successful start or attach status, end the turn.
   The background arm remains the live wait until the cycle ends.
8. Waiting is silent.
9. Never use shell `&` for firstmate supervision.
10. Never bundle the arm onto another command.

Kimi Code CLI (binary `kimi`) supports blockable Stop hooks (exit 2 forces the model to continue, verified 2026-07-18 on 0.26.0).
The primary turn-end guard therefore uses the same exit-2 continue contract as Claude when a managed Stop hook is installed in `$KIMI_CODE_HOME/config.toml`.
Without that managed hook, the background watcher still owns normal wake supervision via pane activity and status events.

Interactive TUI primary sessions are the supported supervision host.
Headless `kimi -p` exits when the prompt finishes and is not a valid primary supervision host.

When this background arm completes, drain the wake queue first, handle any real wake, then re-arm if work remains in flight or X mode still needs polling.
