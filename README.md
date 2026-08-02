# dictado

[![Release](https://img.shields.io/github/v/release/Daf3r/dictado?style=flat-square&color=8b5cf6)](https://github.com/Daf3r/dictado/releases)
[![License](https://img.shields.io/github/license/Daf3r/dictado?style=flat-square&color=8b5cf6)](LICENSE)
![Hyprland only](https://img.shields.io/badge/Hyprland-required-8b5cf6?style=flat-square)
![100% local](https://img.shields.io/badge/inference-100%25%20local-8b5cf6?style=flat-square)

Hold a key, speak, release. The text appears in whatever window has focus.

Local voice dictation for **Hyprland**, powered by [whisper.cpp](https://github.com/ggml-org/whisper.cpp).
No cloud, no account, no telemetry — your audio never leaves the machine.

```
SUPER + G  (hold)  →  🎙 listening  →  release  →  text is inserted
```

> **Demo GIF goes here.**

## Why another dictation script

Dictation on Wayland is a minefield, and most snippets you find break in the two
places that matter: **accented characters** and **Electron apps**. This one
documents every trap it hits, with measurements. The comments in
[`bin/dictado`](bin/dictado) are the real documentation.

The short version of what was learned the hard way:

- **`wtype` drops non-ASCII text in Electron.** Typing `"...y mañana vamos a hacer
  palomitas"` produced `"...y ma"`. Works fine in foot and GTK apps, which is why
  it's easy to miss. The default method sends the text through the clipboard
  instead, where it travels whole.
- **`wtype` can fire your own keybinds.** It sends modifiers through a virtual
  keymap that the compositor resolves against physical keycodes — `Ctrl+Shift+V`
  ended up opening btop, which was bound to `Ctrl+Shift+Escape`. The fix is to
  let Hyprland send the keystroke itself via `hl.dsp.send_shortcut`.
- **WirePlumber will quietly ruin your audio.** It restores the ALSA mixer
  between sessions and pushes the mic to maximum gain. With Capture and Mic
  Boost both maxed (+60 dB) the signal clipped at a mean of −2.5 dB and Whisper
  transcribed distortion. The culprit was Mic Boost, not Capture: Boost at 0 and
  Capture at 100% is the sweet spot. (Capture 40% + Boost 0 undershoots to −49 dB.)
- **Cutting the recording on key release eats your last word.** 250 ms of tail
  rescues it unnoticeably. The start needs no equivalent — measured at 39 ms from
  command to first audio.

## Speed

Measured on an RTX 4060 with the Vulkan backend, `ggml-large-v3-turbo`:

| Path | Latency |
|---|---|
| Model resident in RAM (`whisper-server`) | **~440 ms** |
| First inference after service start | ~8 s (Vulkan shader compilation) |
| Fallback with no service running | ~14 s (loads the model from disk) |

The systemd unit fires a silent warm-up clip on start so that 8 s shader
compilation is never paid by your first real dictation.

`ggml-small` was tried first — 110 ms, but it confused similar-sounding words
often enough to be annoying. `large-v3-turbo` is accurate and still far faster
than anyone speaks.

## Requirements

- **Hyprland** — see [Portability](#portability) below, this is not
  compositor-agnostic
- `whisper.cpp` (`whisper-cli` and `whisper-server` on `PATH`)
- `pipewire` (`pw-record`), `wl-clipboard`, `alsa-utils`, `curl`
- `quickshell` *(optional)* — the visual overlay. Without it dictation works
  exactly the same, just with no on-screen feedback.
- `wtype` *(optional)* — only for `DICTADO_METHOD=type`
- `ffmpeg` *(optional)* — only to generate the warm-up clip at install time

On Arch:

```sh
pacman -S pipewire wl-clipboard alsa-utils curl ffmpeg
yay -S aur/whisper.cpp-vulkan   # or whisper.cpp-cuda, or plain whisper.cpp
```

## Install

```sh
git clone https://github.com/Daf3r/dictado
cd dictado
./install.sh
```

The installer is idempotent and **never overwrites** an existing
`~/.config/dictado/`. It offers to download the model (~1.6 GB) and enables the
`whisper-server` user unit.

Then bind a key in `hyprland.conf`:

```ini
bind  = SUPER, G, exec, dictado start
bindr = SUPER, G, exec, dictado stop
```

Start the overlay on login (optional):

```ini
exec-once = qs -c dictado
```

<details>
<summary>Using the caelestia Lua config instead</summary>

```lua
local dictate = "SUPER + G"

hl.bind(dictate, hl.dsp.exec_cmd("dictado start"))
hl.bind(dictate, hl.dsp.exec_cmd("dictado stop"), { release = true })

-- Run the overlay as a standalone Quickshell instance so shell updates
-- don't clobber it.
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c dictado")
end)
```
</details>

## Configuration

Everything is an environment variable, so you can override any of it per-bind:

| Variable | Default | What it does |
|---|---|---|
| `DICTADO_LANG` | `en` | Language passed to Whisper |
| `DICTADO_MODEL` | `~/.local/share/whisper-models/ggml-large-v3-turbo.bin` | Model path |
| `DICTADO_METHOD` | `paste` | `paste` (clipboard) or `type` (wtype) |
| `DICTADO_PORT` | `8080` | Port of the local `whisper-server` |
| `DICTADO_CARD` | auto-detected | ALSA card of the mic |
| `DICTADO_GAIN` | `100%` | Capture level |
| `DICTADO_PROMPT` | from file | Overrides `~/.config/dictado/prompt.txt` |

### Teaching it your vocabulary

Two layers, in order:

**1. `~/.config/dictado/prompt.txt`** biases the model. Whisper responds far
better to *natural prose* than to word lists — describe what you talk about, in
the style you talk about it:

> I work daily with Linux, Hyprland and Wayland on Arch. I write shell scripts,
> configure systemd units, and use PipeWire for audio.

**2. `~/.config/dictado/corrections.tsv`** is the deterministic fallback, applied
after transcription. For words that sound practically identical, biasing isn't
enough and you need direct substitution:

```tsv
cloud code	Claude Code
hyper land	Hyprland
```

Format is `wrong<TAB>right`, whole words only, case-insensitive.

### Other languages

Set `DICTADO_LANG`, and edit `--language` in
`~/.config/systemd/user/whisper-server.service` to match. Spanish sample configs
ship as `config/prompt.es.txt` and `config/corrections.es.tsv` — copy them over
`prompt.txt` and `corrections.tsv`.

## Portability

**This needs Hyprland**, not just Wayland. The default `paste` method asks the
compositor to send the paste keystroke through `hl.dsp.send_shortcut`, which does
not exist in Sway, river or anything else.

On another compositor, `DICTADO_METHOD=type` will work — at the cost of the
Electron/non-ASCII bug described above. Porting the paste path means finding your
compositor's equivalent of `send_shortcut`; PRs welcome.

## Privacy and security

- **Audio never leaves the machine.** Everything runs against a local
  `whisper-server`; there is no network call beyond `127.0.0.1`.
- **`whisper-server` has no authentication.** The shipped unit binds it to
  `127.0.0.1` on purpose — do not change that to `0.0.0.0`.
- **Dictated text passes through the clipboard** in the default `paste` method,
  so any app watching the clipboard can read it. The previous clipboard contents
  are restored 0.8 s later. If that trade-off doesn't suit you, use
  `DICTADO_METHOD=type`.
- Recordings are written to `$XDG_RUNTIME_DIR/dictado/` and overwritten on every
  use.

## License

MIT
