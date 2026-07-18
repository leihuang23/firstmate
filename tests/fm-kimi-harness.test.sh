#!/usr/bin/env bash
# Behavior tests for Kimi-harness turn-end hook auth, teardown cleanup, and session-lock holder detection.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP_ROOT=$(fm_test_tmproot fm-kimi-harness)

make_spawn_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:-}"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows) exit 0 ;;
  has-session|new-session|new-window|send-keys|kill-window) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  fm_fake_exit0 "$fakebin" treehouse gh-axi gh
  printf '%s\n' "$fakebin"
}

make_spawn_case() {
  local name=$1 case_dir home proj wt fakebin kimi_home id
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(make_spawn_fakebin "$case_dir/fake")
  kimi_home="$case_dir/kimi"
  id="kimi-$name-x1"
  mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config" "$kimi_home"
  printf 'default_model = "kimi-code/kimi-for-coding-highspeed"\n' > "$kimi_home/config.toml"
  printf 'brief\n' > "$home/data/$id/brief.md"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  touch "$home/state/.last-watcher-beat"
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin|$kimi_home|$id"
}

run_kimi_spawn() {
  local home=$1 proj=$2 wt=$3 fakebin=$4 kimi_home=$5 id=$6
  FM_ROOT_OVERRIDE='' FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$wt" TMUX="fake,1,0" \
    FM_KIMI_BRIEF_SETTLE=0 \
    KIMI_CODE_HOME="$kimi_home" PATH="$fakebin:$PATH" \
    "$SPAWN" "$id" "$proj" kimi 2>&1
}

test_kimi_hook_requires_registered_token() {
  local rec case_dir home proj wt fakebin kimi_home id out status hook token target evil evil_target
  rec=$(make_spawn_case hook-auth)
  IFS='|' read -r case_dir home proj wt fakebin kimi_home id <<EOF
$rec
EOF
  out=$(run_kimi_spawn "$home" "$proj" "$wt" "$fakebin" "$kimi_home" "$id")
  status=$?
  expect_code 0 "$status" "kimi spawn should succeed"
  assert_contains "$out" "spawned $id harness=kimi" "kimi spawn did not report success"

  hook="$kimi_home/hooks/fm-turn-end.sh"
  assert_present "$hook" "kimi hook script was not installed"
  assert_grep 'token=' "$wt/.fm-kimi-turnend" "kimi pointer did not contain a token"
  target="$home/state/$id.turn-ended"
  assert_no_grep "$target" "$wt/.fm-kimi-turnend" "kimi pointer exposed the turn-end path"
  token=$(sed -n 's/^token=//p' "$wt/.fm-kimi-turnend")
  assert_present "$kimi_home/hooks/fm-turn-end.d/$token" "kimi auth registry entry was not written"
  assert_grep 'firstmate-managed-kimi-turnend' "$kimi_home/config.toml" "kimi config.toml missing managed Stop hook"

  evil="$case_dir/evil"
  evil_target="$case_dir/evil-target.turn-ended"
  mkdir -p "$evil"
  printf '%s\n' "$evil_target" > "$evil/.fm-kimi-turnend"
  (cd "$evil" && bash "$hook")
  assert_absent "$evil_target" "old-style kimi pointer touched an arbitrary target"

  {
    printf '%s\n' 'ignored'
    printf 'token=%s\n' "$token"
  } > "$wt/.fm-kimi-turnend"
  (cd "$wt" && bash "$hook")
  assert_absent "$target" "kimi pointer accepted token outside the first line"

  printf 'token=%s\n' "$token" > "$wt/.fm-kimi-turnend"
  (cd "$wt" && bash "$hook")
  assert_present "$target" "registered kimi pointer did not touch the task turn-end file"
  pass "kimi global hook requires a firstmate registry token"
}

test_kimi_teardown_removes_pointer_and_token() {
  local rec case_dir home proj wt fakebin kimi_home id out status token
  rec=$(make_spawn_case teardown)
  IFS='|' read -r case_dir home proj wt fakebin kimi_home id <<EOF
$rec
EOF
  out=$(run_kimi_spawn "$home" "$proj" "$wt" "$fakebin" "$kimi_home" "$id")
  status=$?
  expect_code 0 "$status" "kimi spawn should succeed before teardown"
  token=$(sed -n 's/^token=//p' "$wt/.fm-kimi-turnend")

  FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    KIMI_CODE_HOME="$kimi_home" PATH="$fakebin:$PATH" \
    "$TEARDOWN" "$id" --force >/dev/null 2>&1 \
    || fail "kimi teardown failed"

  assert_absent "$wt/.fm-kimi-turnend" "kimi pointer survived teardown"
  assert_absent "$kimi_home/hooks/fm-turn-end.d/$token" "kimi auth token survived teardown"
  assert_absent "$home/state/$id.kimi-turnend-token" "kimi state token survived teardown"
  pass "kimi teardown removes pointer and token state"
}

test_fm_lock_recognizes_kimi_holder() {
  local home fakebin out
  home="$TMP_ROOT/lock-home"
  fakebin=$(fm_fakebin "$TMP_ROOT/lock-fake")
  mkdir -p "$home/state"
  printf '%s\n' "$$" > "$home/state/.lock"
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"comm="*) printf '%s\n' '/Users/leihuang/.kimi-code/bin/kimi'; exit 0 ;;
  *"args="*) printf '%s\n' 'kimi --yolo'; exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/ps"
  out=$(FM_HOME="$home" PATH="$fakebin:$PATH" "$ROOT/bin/fm-lock.sh" status)
  assert_contains "$out" "lock: held by live harness pid" "fm-lock did not recognize kimi as a live holder"
  pass "fm-lock recognizes kimi harness processes"
}

test_kimi_launch_template_and_effort() {
  local rec case_dir home proj wt fakebin kimi_home id out status meta
  rec=$(make_spawn_case launch-flags)
  IFS='|' read -r case_dir home proj wt fakebin kimi_home id <<EOF
$rec
EOF
  out=$(FM_ROOT_OVERRIDE='' FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$wt" TMUX="fake,1,0" \
    FM_KIMI_BRIEF_SETTLE=0 \
    KIMI_CODE_HOME="$kimi_home" PATH="$fakebin:$PATH" \
    "$SPAWN" "$id" "$proj" --harness kimi --model 'kimi-code/kimi-for-coding-highspeed' --effort high 2>&1)
  status=$?
  expect_code 0 "$status" "kimi spawn with model/effort should succeed"
  assert_contains "$out" "spawned $id harness=kimi" "kimi spawn with flags did not report success"
  meta="$home/state/$id.meta"
  assert_grep 'model=kimi-code/kimi-for-coding-highspeed' "$meta" "meta missing model"
  assert_grep 'effort=high' "$meta" "meta missing effort"
  pass "kimi records model/effort and launches"
}

test_kimi_hook_requires_registered_token
test_kimi_teardown_removes_pointer_and_token
test_fm_lock_recognizes_kimi_holder
test_kimi_launch_template_and_effort
