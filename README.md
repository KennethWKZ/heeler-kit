# heeler-kit

Use the coding agents running in herdr on your Mac from your iPhone or iPad, with the
[Heeler](https://github.com/ZingerLittleBee/Heeler) app, at home, in the office or on mobile data.

The phone reaches the Mac over [Tailscale](https://tailscale.com). On the Mac, Tailscale runs in
userspace mode: no VPN, no network extension, no admin rights, so it doesn't clash with a company VPN.
Your code and terminal output go straight from the Mac to the phone over SSH.

heeler-kit is an unofficial helper. It is not part of Heeler, herdr or Tailscale and isn't made by their
authors; it sets them up on a Mac the way described here.

## What you need

- A Mac with Apple silicon or Intel, Homebrew, herdr (running), Node 20 or newer.
- Remote Login on: System Settings > General > Sharing > Remote Login. Allow only your own user.
- A Tailscale account (free for personal use) and the Heeler app on the phone.
- On a company Mac: your security team's OK. This adds a way into the Mac from your phone.

## Install

```sh
git clone https://github.com/KennethWKZ/heeler-kit.git
cd heeler-kit
bash install.sh
heeler-kit install
```

Updating later: `git pull`, then `bash install.sh` again.

`heeler-kit install` stops and prints a Tailscale sign-in link. Open it, sign in, then run
`heeler-kit install` again. It finishes the setup and installs the Heeler herdr plugin.

Then:

1. **Lock the tailnet to SSH only.** `heeler-kit policy` prints an access policy. Paste it in the
   Tailscale admin console > Access controls, replacing what is there, and save. Do this before the
   phone connects: in userspace mode, every device in the tailnet can otherwise reach every service
   on the Mac, including ones that only listen on `127.0.0.1`.
2. **Pair the phone.** `heeler-kit pair` shows a code in herdr. Scan it in the Heeler app. If a phone is
   already paired it says so instead (`--force` shows a code for another device).
3. **Add the tailnet in Heeler.** Settings > Overlay Networks > Add Network > Tailscale, sign in with
   the same account. Edit the Host > More Options > Network: your tailnet > Choose from Tailnet > your
   Mac, port 22. The Host's User must be your Mac login name exactly (`heeler-kit status` prints it).
4. **Turn off SSH passwords.** `heeler-kit harden-ssh` prints two `sudo` lines; run them.
5. **Test** with the phone's Wi-Fi off.

`heeler-kit status` shows what is set up, whether a phone is paired, and where open sessions come from.
Every command is safe to run again.

## Good to know

- The Mac is reachable only while you are logged in and it is awake.
- The Heeler plugin is pinned to a tested commit (`heeler-kit version`).
- Remove it with `heeler-kit uninstall` (`--purge` also signs the Mac out of Tailscale and removes it).
  The phone's key stays in `~/.ssh/authorized_keys` until you delete that line.
- What you send from Heeler reaches the agent through herdr's `agent.prompt`, which pastes the text
  (bracketed paste) and then presses Enter. So it is a paste, not typing: shortcuts that react to single
  keys in the agent (such as a plugin's number hotkeys above Claude Code's prompt) don't fire. Sending
  `3` from the phone sends the text "3". A plugin that should react to the phone has to read the submitted
  prompt instead of key presses. Typing in Heeler's terminal view goes straight into the terminal instead
  (herdr logs it as a terminal attach, not `agent.prompt`).

## Working from the phone

- **Approve permission prompts in the terminal view.** When Claude Code asks "Do you want to proceed?", switch
  to Heeler's terminal view and press Enter. The chat box can't answer it: herdr refuses `agent.prompt` while
  an agent waits on a dialog (`agent_blocked`), so nothing reaches the prompt. A raw Enter key approves it.
- **Short `!` lines instead of long ones.** Copying a long command on a phone is fiddly. One way round it:
  scripts save each command they want you to run in a file named by a short hash of the command, and print
  `! ok 7f3a2c  # <the command>`. A small `ok` script checks the hash and runs the command once. You type
  `! ok 7f3a2c`, and pasting the whole line still works, because the shell skips the `#` part. heeler-kit
  doesn't install such a script.
- **Sign-ins that need a code, such as AWS.** `!` commands don't take typed input, so run these in a plain
  shell pane in Heeler: `aws login --remote --profile <profile>`, or `aws sso login --profile <profile>
  --use-device-code` for IAM Identity Center. Open the link on the phone, sign in there, and paste the code
  back if it asks. With several AWS accounts, name the profile every time, and ask your agent to put it in
  the line it gives you. The sign-in link is long and wraps over several lines in the phone's narrow view:
  long-press to copy all of it, or use a wrapper that prints it as one short link.
- Optional: `bash install.sh --with-next-steps` also installs the next-steps plugin for Claude Code from
  GitHub at a tested release (`KennethWKZ/next-steps#v1.0.2`, MIT; needs internet access and jq). After
  each answer it suggests up to three next prompts and shows them as one block in the transcript (a
  header, then each suggestion on its own line, wrapped under its own text even in the phone's narrow
  view), so you can read and copy them on the phone. Pick from Heeler by sending just numbers: `3`,
  `1,2`, or `9` for all. The list survives `/reload-plugins`, so a number sent right after a reload
  still picks from it. It turns off any other next-steps copy (such as `next-steps@claude-community`)
  and removes the copy older kits installed from the zip; needs a recent Claude Code.
- If you use Claude Code, `install.sh` also adds a `heeler-remote` skill: ask Claude to set up or check
  Heeler and it runs these steps, handing you the sign-in, the policy and the `sudo` lines.

## Licence

MIT, see `LICENSE`.
