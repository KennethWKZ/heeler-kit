#!/bin/bash
# Tests for heeler-kit on a Mac that already runs it. Never signs anything in, never touches the
# live LaunchAgent, its state or the Heeler plugin: the fresh-install path runs under a test label
# and a temp state dir, stops at the sign-in link, then uninstalls with --keep-plugin.
# Usage: bash test.sh   (HEELER_KIT_PACK=<path to a pack script> adds the zip checks)
set -u
cd "$(dirname "$0")"
KIT=./heeler-kit
fail=0; n=0
t() { # $1 = name, $2 = condition (shell), run in a subshell
  n=$((n + 1))
  if ( eval "$2" ) >/dev/null 2>&1; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); fi
}

t "syntax (bash 3.2)" "/bin/bash -n $KIT"
t "help lists every command" "$KIT help | grep -q harden-ssh && $KIT help | grep -q keep-plugin"
t "unknown command exits 1" "! $KIT bogus"
t "status runs" "$KIT status"
# 2026-11-21: a `grep && printf` loop ending made set -e stop status silently halfway. status must reach
# its last section (the paired-device lines) on this Mac.
t "status runs to the end" "$KIT status | grep -Eq 'Heeler paired|no phone registered'"

# Remote Login access, with the lookup replaced by HEELER_KIT_SSH_ALLOWED.
me=$(id -un)
t "access: only me is ok" "HEELER_KIT_SSH_ALLOWED='$me' $KIT __access | grep -q 'allows only $me'"
t "access: another account warns and names it" "HEELER_KIT_SSH_ALLOWED='$me otheruser' $KIT __access | grep -q '\[!!\].*also lets in: otheruser'"
t "access: me missing warns" "HEELER_KIT_SSH_ALLOWED='otheruser' $KIT __access | grep -q \"doesn't allow $me\""
t "access: nobody allowed warns" "HEELER_KIT_SSH_ALLOWED='' $KIT __access | grep -q \"doesn't allow $me\""
t "access: live lookup completes" "$KIT __access | grep -Eq '\[ok\]|\[!!\]'"

live_running=$(launchctl print "gui/$(id -u)/dev.heeler.tailscaled" 2>/dev/null | awk '$1 == "state" { print $3; exit }')
if $KIT status 2>/dev/null | grep -q 'tailnet .*online='; then
  pol=$(mktemp)
  $KIT policy > "$pol"
  t "policy is valid JSON once comments are stripped" "sed -E 's#^[[:space:]]*//.*##' '$pol' | jq -e . "
  t "policy grants tcp:22 only" "sed -E 's#^[[:space:]]*//.*##' '$pol' | jq -e '.grants | length == 1 and .[0].ip == [\"tcp:22\"]'"
  t "policy tests deny no port 22" "sed -E 's#^[[:space:]]*//.*##' '$pol' | jq -e '(.tests[0].deny // []) | map(endswith(\":22\")) | any | not'"
  rm -f "$pol"
else
  echo "skip policy tests: this Mac isn't signed in to a tailnet"
fi

# Paired-device detection from canned lsof output (the shape of real lines, captured 2026-11-21; the addresses are made up).
lsof_sample=$(mktemp)
cat > "$lsof_sample" <<'EOF'
COMMAND     PID       USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
sshd-sess 17502 user    7u  IPv4 0xb349622b98aeb4f7      0t0  TCP 192.168.50.10:22->192.168.50.20:64071 (ESTABLISHED)
sshd-sess 17502 user    8u  IPv4 0xb349622b98aeb4f7      0t0  TCP 192.168.50.10:22->192.168.50.20:64071 (ESTABLISHED)
sshd-sess 17600 user    7u  IPv4 0xb349622b98aeb4f8      0t0  TCP 127.0.0.1:22->127.0.0.1:49329 (ESTABLISHED)
tailscale 20065 user   19u  IPv4 0x615f7fda3b6b2934      0t0  TCP 127.0.0.1:49329->127.0.0.1:22 (ESTABLISHED)
ssh       20100 user    3u  IPv4 0x615f7fda3b6b2999      0t0  TCP 192.168.50.10:50000->203.0.113.9:22 (ESTABLISHED)
sshd-sess 17700 user    7u  IPv4 0xb349622b98aeb4f9      0t0  TCP 192.168.50.10:22->198.51.100.7:40000 (ESTABLISHED)
EOF
live_out=$(HEELER_KIT_LSOF_FILE="$lsof_sample" $KIT __live)
t "LAN session counted once despite two fd lines" "printf '%s' \"\$live_out\" | grep -qx 'local network (192.168.50.20), 1 session(s)'"
t "tailscaled loopback connection counts as the tailnet" "printf '%s' \"\$live_out\" | grep -q '^the tailnet.*, 1 session(s)'"
t "public address labelled internet" "printf '%s' \"\$live_out\" | grep -qx 'internet (198.51.100.7), 1 session(s)'"
t "outgoing ssh client ignored" "! printf '%s' \"\$live_out\" | grep -q 203.0.113.9"
t "sshd loopback side not listed" "! printf '%s' \"\$live_out\" | grep -q 127.0.0.1"
printf 'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n' > "$lsof_sample"
t "no sessions gives empty output" "[ -z \"\$(HEELER_KIT_LSOF_FILE='$lsof_sample' $KIT __live)\" ]"
rm -f "$lsof_sample"

# pair on a Mac with a registered phone: says so and opens no code (counted in the plugin's log).
reg=$(jq '.devices // [] | length' "$HOME/.config/herdr/plugins/config/heeler/notifications.json" 2>/dev/null || echo 0)
if [ "${reg:-0}" -gt 0 ]; then
  pairs() { herdr plugin log list --plugin heeler --limit 50 2>/dev/null | jq '[.. | objects | select(.action_id? == "pair")] | length'; }
  before=$(pairs); pair_out=$($KIT pair 2>&1); sleep 1; after=$(pairs)
  t "pair on a paired Mac says so" "printf '%s' \"\$pair_out\" | grep -q 'Already paired'"
  t "pair on a paired Mac opens no code" "[ '$before' = '$after' ]"
else
  echo "skip pair tests: no phone registered on this Mac"
fi

# Fresh install path, isolated.
export HEELER_KIT_LABEL=dev.heeler.tailscaled.kittest
export HEELER_KIT_STATE="${TMPDIR:-/tmp}/heeler-kittest-$$"
out=$($KIT install --hostname kittest-node 2>&1); rc=$?
t "fresh install stops for sign-in (exit 3)" "[ $rc -eq 3 ]"
t "fresh install prints a sign-in link" "printf '%s' \"\$out\" | grep -q 'https://login.tailscale.com/'"
t "test LaunchAgent is running" "launchctl print gui/$(id -u)/$HEELER_KIT_LABEL"
t "state dir is private (700)" "[ \"\$(stat -f %Lp '$HEELER_KIT_STATE')\" = 700 ]"
out2=$($KIT install --hostname kittest-node 2>&1)
t "second run reuses the same link" "[ \"\$(printf '%s' \"\$out\" | grep -o 'https://login[^ ]*')\" = \"\$(printf '%s' \"\$out2\" | grep -o 'https://login[^ ]*')\" ]"
$KIT uninstall --keep-plugin >/dev/null 2>&1
t "uninstall removes the test LaunchAgent" "! launchctl print gui/$(id -u)/$HEELER_KIT_LABEL"
t "uninstall removes the test plist" "[ ! -f \"\$HOME/Library/LaunchAgents/$HEELER_KIT_LABEL.plist\" ]"
pkill -f "$HEELER_KIT_STATE/tailscaled.socket up" 2>/dev/null
rm -rf "$HEELER_KIT_STATE"
rm -f "$HOME/Library/Logs/$HEELER_KIT_LABEL.log"
unset HEELER_KIT_LABEL HEELER_KIT_STATE

t "--keep-plugin left the Heeler plugin" "jq -e '.[] | select(.plugin_id == \"heeler\")' \"\$HOME/.config/herdr/plugins.json\" || ! command -v herdr"
if [ -n "$live_running" ]; then
  t "live LaunchAgent untouched" "[ \"\$(launchctl print gui/$(id -u)/dev.heeler.tailscaled | awk '\$1 == \"state\" { print \$3; exit }')\" = '$live_running' ]"
fi

# Opt-in (restarts the live tailscaled for about a second): install right after a daemon restart must
# keep the Mac's tailnet name. 2026-11-21 it renamed the Mac by deciding on the transient Starting state.
if [ "${TEST_RESTART_LIVE:-}" = 1 ] && [ -n "$live_running" ]; then
  sock="$HOME/.local/share/heeler-tailscale/tailscaled.socket"
  name_before=$("$(brew --prefix tailscale)/bin/tailscale" --socket="$sock" status --json | jq -r .Self.HostName)
  launchctl kickstart -k "gui/$(id -u)/dev.heeler.tailscaled"
  $KIT install >/dev/null 2>&1
  name_after=$("$(brew --prefix tailscale)/bin/tailscale" --socket="$sock" status --json | jq -r .Self.HostName)
  t "install after a restart keeps the name ($name_before)" "[ '$name_before' = '$name_after' ]"
fi

# Run install.sh --with-next-steps under a throwaway HOME and Claude config dir: next-steps comes from GitHub
# at the tag install.sh pins. The real ~/.claude is only read. With HEELER_KIT_PACK set to a pack script
# (the zip builder, kept outside this repo), the kit is packed first and the install runs from the unpacked
# zip; otherwise from a copy of this folder. Needs the claude command and GitHub; skipped without them.
ns_source=$(sed -n "s/^NEXT_STEPS_SOURCE='\(.*\)'$/\1/p" install.sh)
ns_id=$(sed -n "s/^NEXT_STEPS_ID='\(.*\)'$/\1/p" install.sh)
ns_tag=${ns_source#*#}
ns_market=${ns_id#*@}
if command -v claude >/dev/null && git ls-remote --exit-code --tags "https://github.com/${ns_source%%#*}.git" "refs/tags/$ns_tag" >/dev/null 2>&1; then
  pk=$(mktemp -d "${TMPDIR:-/tmp}/heeler-packtest.XXXXXX")
  real_mk="$HOME/.claude/plugins/known_marketplaces.json"
  real_before=$(cksum "$real_mk" 2>/dev/null)
  if [ -n "${HEELER_KIT_PACK:-}" ]; then
    HEELER_KIT_DIR="$PWD" HEELER_PACK_OUT="$pk/out" bash "$HEELER_KIT_PACK" -test >/dev/null 2>&1; rc=$?
    t "pack succeeds" "[ $rc -eq 0 ]"
    zip=$(ls "$pk"/out/*.zip 2>/dev/null | head -1)
    list=$(unzip -Z1 "$zip" 2>/dev/null)
    t "zip has install.sh" "printf '%s\n' \"\$list\" | grep -qx 'heeler-kit/install.sh'"
    t "zip doesn't bundle next-steps/" "! printf '%s\n' \"\$list\" | grep -q 'heeler-kit/next-steps/'"
    unzip -q "$zip" -d "$pk/unz"
  else
    echo "skip zip checks: HEELER_KIT_PACK not set (install checks run from a copy of this folder)"
    mkdir -p "$pk/unz/heeler-kit"
    cp -R heeler-kit install.sh README.md skill "$pk/unz/heeler-kit/"
  fi
  kit="$pk/unz/heeler-kit"
  t "install.sh pins owner/repo#tag" "printf '%s' '$ns_source' | grep -Eq '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+#[A-Za-z0-9._-]+$'"

  mkdir -p "$pk/home/.claude"
  as_home() { HOME="$pk/home" CLAUDE_CONFIG_DIR="$pk/home/.claude" "$@"; }
  inst() { as_home bash "$kit/install.sh" "$@"; }
  ids() { as_home claude plugin list --json 2>/dev/null | jq -r '.[] | "\(.id) \(.version) \(.enabled)"'; }
  ref() { jq -r --arg m "$ns_market" '.extraKnownMarketplaces[$m].source.ref // empty' "$pk/home/.claude/settings.json" 2>/dev/null; }
  inst --bogus >/dev/null 2>&1; rc=$?
  t "install.sh rejects an unknown option" "[ $rc -ne 0 ]"
  t "a rejected run installs nothing" "[ ! -e '$pk/home/.local/bin/heeler-kit' ]"

  # An older kit's install: next-steps@heeler-kit from a folder marketplace, plus community's copy on.
  old="$pk/home/.local/share/heeler-kit/next-steps"
  mkdir -p "$old"
  git -C "$pk" clone -q --depth 1 --branch "$ns_tag" "https://github.com/${ns_source%%#*}.git" src 2>/dev/null
  cp -R "$pk/src/." "$old/" && rm -rf "$old/.git"
  jq '.name = "heeler-kit"' "$pk/src/.claude-plugin/marketplace.json" > "$old/.claude-plugin/marketplace.json"
  as_home claude plugin marketplace add "$old" >/dev/null 2>&1 && as_home claude plugin install next-steps@heeler-kit >/dev/null 2>&1
  t "old-style next-steps@heeler-kit set up for the move" "ids | grep -q '^next-steps@heeler-kit '"

  inst --with-next-steps >/dev/null 2>&1; rc=$?
  t "install.sh --with-next-steps succeeds" "[ $rc -eq 0 ]"
  t "$ns_id installed and enabled" "ids | grep -q '^$ns_id .* true$'"
  t "marketplace pinned to the tag ($ns_tag)" "[ \"\$(ref)\" = '$ns_tag' ]"
  t "old next-steps@heeler-kit removed" "! ids | grep -q '^next-steps@heeler-kit '"
  t "old heeler-kit marketplace removed" "! as_home claude plugin marketplace list --json | jq -e 'any(.[]; .name == \"heeler-kit\")'"
  t "old copy folder removed" "[ ! -e '$old' ]"
  t "only one next-steps enabled" "[ \"\$(ids | grep -c '^next-steps@.* true$')\" = 1 ]"

  # A marketplace left at another ref (say main) is moved to the tag.
  as_home claude plugin marketplace remove "$ns_market" >/dev/null 2>&1
  as_home claude plugin marketplace add "${ns_source%%#*}#main" >/dev/null 2>&1
  inst --with-next-steps >/dev/null 2>&1; rc=$?
  t "a second run succeeds and moves main to the tag" "[ $rc -eq 0 ] && [ \"\$(ref)\" = '$ns_tag' ] && ids | grep -q '^$ns_id .* true$'"
  inst >/dev/null 2>&1
  t "install.sh without the option leaves the plugin as it was" "ids | grep -q '^$ns_id .* true$'"
  t "real Claude plugin config untouched" "[ \"\$(cksum '$real_mk' 2>/dev/null)\" = '$real_before' ]"
  rm -rf "$pk"
else
  echo "skip pack and next-steps tests: no claude command, or GitHub/tag ${ns_source} not reachable"
fi

printf '\n%d tests, %d failed\n' "$n" "$fail"
[ "$fail" = 0 ]
