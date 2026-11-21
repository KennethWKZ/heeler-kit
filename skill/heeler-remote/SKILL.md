---
name: heeler-remote
description: Heeler phone access to this Mac's herdr agents, run with the heeler-kit command (Tailscale in userspace mode, a tailnet policy that allows SSH only). Use to set it up, pair a phone, check why the phone can't connect, or remove it.
---

# Heeler remote access with heeler-kit

`heeler-kit` (in `~/.local/bin`) does every step on the Mac; `heeler-kit help` lists the commands. Each command
is safe to run again, and exit code 3 means it is waiting for the person. Your job is to run it, hand the person
the parts only they can do, and confirm each one landed with `heeler-kit status`.

## Set up

1. `heeler-kit install`. It checks Remote Login, herdr (server running), Node 20+, then installs the Homebrew
   `tailscale` formula, a LaunchAgent, and starts the sign-in. Any `[!!]` line is the person's to fix:
   - Remote Login off: System Settings > General > Sharing > Remote Login, allowed for their user only.
   - `Remote Login also lets in: <accounts>`: in that same (i) panel, Only these users = just their account
     (remove Administrators), then they run `sudo dsmemberutil flushcache`; sshd reads the cached membership.
   - herdr server not running: they start `herdr` in a terminal tab.
2. Exit 3 with a `login.tailscale.com` link: give the person the link. They sign in with the account their
   phone will use and approve the device if asked. Then run `heeler-kit install` again; done when it prints
   `signed in to the tailnet as <name> (<100.x IP>)` and the Heeler plugin line is `[ok]`.
3. `heeler-kit policy`: give the person the whole output to paste in the Tailscale admin console > Access
   controls, replacing what is there. It allows tcp:22 to this Mac and nothing else; its `tests` block makes the
   save fail if a local service would be reachable. This step comes before the phone connects over the tailnet,
   because userspace mode exposes services bound to 127.0.0.1 (proxies, databases) to every tailnet device.
4. `heeler-kit pair`. On a Mac where a phone is already paired (registered with the plugin, or an SSH session
   open now) it says so and shows no code; that step is done. Otherwise the code shows in their herdr window and
   they scan it in the Heeler app. `--force` shows a code for another device.
5. In Heeler, the person: Settings > Overlay Networks > Add Network > Tailscale, same account; then edit the
   Host > More Options > Network: that tailnet > Choose from Tailnet > this Mac, port 22. Done when it connects
   with the phone's Wi-Fi off.
6. `heeler-kit harden-ssh`. If SSH still takes passwords, it prints two sudo lines: the person runs them in their
   own terminal tab. Done when `heeler-kit status` shows `SSH password logins off`.

## Rules

- Sudo, passwords and anything in `~/.ssh` belong to the person: hand them the line, then verify with `status`.
- The only routes in are the tailnet (or the local network). Keep port 22 closed on routers and firewalls.
- The Heeler plugin stays on the commit pinned in `heeler-kit` (`heeler-kit version`). A newer one goes on only
  after the person has tested it and the pin in the script moves.

## What the phone sends

A prompt sent from Heeler reaches the agent through herdr's `agent.prompt` API, not `herdr pane send-text` or
`send-keys`: each send is an `api.request.start ... method="agent.prompt"` line in
`~/.config/herdr/herdr-server.log`, with an upper-case UUID request id. herdr follows the pane's live
bracketed-paste mode, so in Claude Code (which turns that mode on) the text arrives as a paste followed by Enter:
`ESC[200~3ESC[201~` then `\r` (byte capture in a throwaway pane, 2026-11-21). So the phone's text never counts as
key presses: anything in the session that reacts to single keys (band hotkeys, a `prompt.edit` hook keyed on
typing) doesn't see it, and a hook has to act on the submitted prompt (`prompt.submit`) instead. What the phone
can't see is what the pane doesn't show as text: a plugin that should work from the phone also prints its
choices into the transcript. `herdr pane send-text`, by contrast, writes the raw text with no paste markers.
Heeler's terminal view is a second path: it attaches straight to the pane's terminal (`direct terminal client
connected` and `terminal attach client connected ... terminal_id=...` in the same log), and what is typed there makes
no `agent.prompt` line. A number typed there still reached `prompt.submit` as text in a test on 2026-11-21; the exact
bytes on that path were not captured.
The kit's optional next-steps plugin works this way (`bash install.sh --with-next-steps` from the unpacked kit
installs it from GitHub at the tag in `NEXT_STEPS_SOURCE`; the person decides, as it turns off any other
next-steps copy, such as `next-steps@claude-community`): send just `3`, `1,2` or `9` for all. It keeps
its list in the session's `$.state`, so the list survives `/reload-plugins` and a number sent right after a reload
still swaps; `/clear` drops it. It shows each list as one block in the transcript, a placed row (`$.ui.place`)
with the header and one suggestion per line, each wrapping under its own text (checked at Heeler's 62 columns).
`$.ui.log` can't do that: it keeps an entry to one line and turns a line break into U+FFFD. Placed rows are display
only, so check them with `herdr pane read`, not the transcript file.

## When the person is on the phone

- **A permission dialog waits on them:** tell them to switch to Heeler's terminal view and press Enter. The chat
  box can't answer it: `agent.prompt` to a blocked agent returns `agent_blocked` and sends nothing. Tested
  2026-11-21 in a throwaway herdr tab: `herdr agent prompt <agent> "1"` was refused, and `herdr agent send-keys
  <agent> enter` approved the dialog and the command ran. An `ask` rule prompts even in bypass mode.
- **A command for them to run with `!`:** keep it short. If an `ok` runner is installed (`command -v ok`) and the
  repo's scripts save pending commands for it, give the line exactly as the script printed it (`! ok <id>  #
  <command>`), and never run `ok` yourself. Otherwise give one line that starts with `cd <repo root> &&`.
- **A sign-in that needs a code typed back** (AWS `aws login --remote`): `!` can't take typed input, so give the
  exact line for a plain shell pane, with the profile the failing command used: `aws login --remote --profile
  <profile>`, or the person's wrapper if they have one (for example `aws-login <profile> --remote`). One line per
  expired profile. Never open, fill in or read that sign-in yourself, and never ask for the code.

## Phone can't connect

Run `heeler-kit status` first: its last lines say whether a phone is registered and where open SSH sessions come
from (`local network`, `internet`, or `the tailnet`; a tailnet session reaches sshd as 127.0.0.1, so it never shows
the phone's 100.x address). Then, by symptom:

- Tailnet line not `online=true`: the Mac sleeps or isn't logged in (the LaunchAgent runs only while the person
  is logged in and the Mac is awake). Log: `~/Library/Logs/heeler-tailscaled.log`.
- No `peer heeler` line: Heeler hasn't joined the same tailnet; the person signs in again under Overlay Networks.
- Peer online but SSH times out: the policy is missing the grant, or the Host uses the phone's address instead of
  this Mac's. `heeler-kit policy` again and compare with what is saved.
- `authentication failed` in Heeler: first the Host's User, which must be the Mac's login name exactly (`status`
  prints it; on 2026-11-21 a wrong User was the whole cause). Then the key: it may be gone from
  `~/.ssh/authorized_keys` (rewritten by hand); `heeler-kit pair --force`, the person scans, pairing appends it.
  A registered phone in `status` doesn't prove the key is still there.
- Host key warning in Heeler: trust it only if the fingerprint matches this Mac; ask the person.

## Remove

`heeler-kit uninstall` removes the plugin and the LaunchAgent; `--keep-plugin` keeps Heeler working on the local
network; `--purge` also signs the Mac out of the tailnet and removes the formula. The phone's key in
`~/.ssh/authorized_keys`, the tailnet policy and Remote Login are the person's to remove.
