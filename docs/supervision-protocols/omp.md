Mode: omp extension background wake.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
2. Confirm the omp primary auto-loaded both project extensions (plain `omp`; `.omp/extensions/` auto-loads with no trust gate); if not, restart with `-e __FM_OMP_TURNEND_EXT__ -e __FM_OMP_EXT__`.
3. Arm supervision with the `fm_watch_arm_omp` tool.
   Use `/fm-watch-arm-omp` only as a human-entered fallback.
   Never run `bin/fm-watch-arm.sh` through omp's bash tool because that foreground arm can wedge the agent and bypasses extension-owned cleanup.
4. If the extension says no live session holds the lock, run `bin/fm-session-start.sh` to reclaim the session lock, then call `fm_watch_arm_omp` again.
5. The extension starts `bin/fm-watch-arm.sh --restart`, keeps the child attached to the live omp process, and sends a follow-up user message when the child exits with an actionable watcher reason.
6. After handling that wake, obey the turn-end guard's bounded re-arm continuation when work remains in flight; [`watcher-continuity.md`](../watcher-continuity.md) owns the ordering and residual active-turn limit.
7. If the extension says the watcher is already healthy, do not start another cycle.
8. If the extension reports a watcher failure, drain queued wakes, inspect the failure text, and restart omp with both extensions loaded if needed.
9. Never use shell `&` for watcher supervision.
   The arm mechanism above is extension-owned, not a model tool call, but a manual recovery probe that backgrounds, pipes, or bundles the arm is denied automatically by the PreToolUse seatbelt (`bin/fm-arm-pretool-check.sh`, wired into the turn-end guard extension at `__FM_OMP_TURNEND_EXT__`).

The turn-end guard extension lives at `__FM_OMP_TURNEND_EXT__`.
The watcher extension lives at `__FM_OMP_EXT__`.
Both are tracked, project-local `.omp/extensions/*.ts` files that omp auto-discovers with no trust gate; `bin/fm-session-start.sh` reports when the running omp session has not loaded both required extensions.
