#!/bin/bash
# Installs the heeler-kit command into ~/.local/bin, and the heeler-remote skill for Claude Code
# when ~/.claude exists. Changes nothing else; run `heeler-kit install` afterwards.
#
# --with-next-steps also installs the next-steps Claude Code plugin from GitHub at a tested release
# (NEXT_STEPS_SOURCE below), turns off any other next-steps copy that is on, and removes the
# next-steps@heeler-kit copy older kits installed from the zip. Needs internet access, the claude
# command and jq. Safe to run again; a kit with a newer tag moves the plugin to it.
# Usage: bash install.sh [--with-next-steps]
set -eu
cd "$(dirname "$0")"

# The tested release: change the tag here to move everyone to a newer one.
NEXT_STEPS_SOURCE='KennethWKZ/next-steps#v1.0.1'
NEXT_STEPS_ID='next-steps@kennethwkz'

with_next_steps=0
for arg in "$@"; do
  case "$arg" in
    --with-next-steps) with_next_steps=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option $arg (try --help)" >&2; exit 1 ;;
  esac
done

# Checked before anything is installed, so a bad run changes nothing.
if [ "$with_next_steps" = 1 ]; then
  command -v claude >/dev/null || { echo "install.sh: --with-next-steps needs the claude command (Claude Code) on PATH" >&2; exit 1; }
  command -v jq >/dev/null || { echo "install.sh: --with-next-steps needs jq (macOS 15 and later include it; else brew install jq)" >&2; exit 1; }
fi

mkdir -p "$HOME/.local/bin"
install -m 755 heeler-kit "$HOME/.local/bin/heeler-kit"
echo "installed ~/.local/bin/heeler-kit ($("$HOME/.local/bin/heeler-kit" version))"

if [ -d "$HOME/.claude" ]; then
  mkdir -p "$HOME/.claude/skills/heeler-remote"
  install -m 644 skill/heeler-remote/SKILL.md "$HOME/.claude/skills/heeler-remote/SKILL.md"
  echo "installed the heeler-remote skill (~/.claude/skills/heeler-remote); restart Claude Code to load it"
fi

if [ "$with_next_steps" = 1 ]; then
  market=${NEXT_STEPS_ID#*@}         # the marketplace the plugin comes from
  tag=${NEXT_STEPS_SOURCE#*#}        # the release it is pinned to
  settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  plugins() { claude plugin list --json 2>/dev/null || echo '[]'; }
  has_market() { claude plugin marketplace list --json 2>/dev/null | jq -e --arg m "$1" 'any(.[]; .name == $m)' >/dev/null; }

  # Older kits installed a copy from the zip as next-steps@heeler-kit: remove it, its marketplace and its folder.
  if plugins | jq -e 'any(.[]; .id == "next-steps@heeler-kit")' >/dev/null; then
    claude plugin uninstall next-steps@heeler-kit >/dev/null
    echo "removed next-steps@heeler-kit (the copy older kits installed from the zip)"
  fi
  if has_market heeler-kit; then claude plugin marketplace remove heeler-kit >/dev/null; fi
  rm -rf "$HOME/.local/share/heeler-kit/next-steps"
  rmdir "$HOME/.local/share/heeler-kit" 2>/dev/null || true

  # The marketplace at the tested tag. Adding it again with another ref changes nothing, so a
  # marketplace at another ref (or none) is removed first; that also uninstalls its plugin.
  ref=$(jq -r --arg m "$market" '.extraKnownMarketplaces[$m].source.ref // empty' "$settings" 2>/dev/null || true)
  if has_market "$market" && [ "$ref" != "$tag" ]; then
    claude plugin marketplace remove "$market" >/dev/null
    echo "moving next-steps from ${ref:-its current source} to $tag"
  fi
  has_market "$market" || claude plugin marketplace add "$NEXT_STEPS_SOURCE" >/dev/null

  # Two next-steps plugins would both draw a list and share the 1/2/3/9/0 keys: turn the others off.
  for other in $(plugins | jq -r --arg id "$NEXT_STEPS_ID" '.[] | select(.enabled and (.id | startswith("next-steps@")) and .id != $id) | .id'); do
    claude plugin disable "$other" >/dev/null
    echo "turned off $other ($NEXT_STEPS_ID replaces it)"
  done
  claude plugin install "$NEXT_STEPS_ID" >/dev/null
  version=$(plugins | jq -r --arg id "$NEXT_STEPS_ID" '.[] | select(.id == $id) | .version')
  echo "installed $NEXT_STEPS_ID $version from GitHub ($tag); run /reload-plugins in open Claude Code sessions"
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "note: ~/.local/bin isn't on PATH; add it to your shell profile" ;;
esac
echo
echo "Next: heeler-kit install"
