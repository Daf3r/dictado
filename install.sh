#!/usr/bin/env bash
# dictado installer. Idempotent: safe to re-run, never overwrites your configs.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
MODEL_DIR="$DATA_DIR/whisper-models"
MODEL="$MODEL_DIR/ggml-large-v3-turbo.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"

say()  { printf '\033[1;35m::\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1"; }

# --- dependency check ----------------------------------------------------
missing=()
for c in pw-record whisper-cli wl-copy wl-paste hyprctl amixer curl; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
    warn "Missing commands: ${missing[*]}"
    warn "On Arch: pacman -S pipewire wl-clipboard alsa-utils curl  +  whisper.cpp (AUR)"
    exit 1
fi
command -v wtype >/dev/null 2>&1 || warn "wtype not found — only needed for DICTADO_METHOD=type"
command -v qs    >/dev/null 2>&1 || warn "quickshell not found — the visual overlay will be skipped"

# --- script --------------------------------------------------------------
say "Installing dictado into $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/dictado" "$BIN_DIR/dictado"

# --- overlay -------------------------------------------------------------
if command -v qs >/dev/null 2>&1; then
    say "Installing the overlay into $CFG_DIR/quickshell/dictado"
    mkdir -p "$CFG_DIR/quickshell/dictado"
    install -m 644 "$SRC/overlay/shell.qml" "$CFG_DIR/quickshell/dictado/shell.qml"
fi

# --- config (never overwritten) ------------------------------------------
mkdir -p "$CFG_DIR/dictado"
for f in prompt.txt corrections.tsv; do
    if [[ -e "$CFG_DIR/dictado/$f" ]]; then
        say "Keeping your existing $f"
    else
        install -m 644 "$SRC/config/$f" "$CFG_DIR/dictado/$f"
        say "Created $CFG_DIR/dictado/$f"
    fi
done

# --- model ---------------------------------------------------------------
mkdir -p "$MODEL_DIR"
if [[ -f "$MODEL" ]]; then
    say "Model already present ($(du -h "$MODEL" | cut -f1))"
else
    warn "The model is missing (~1.6 GB download)."
    # Never abort here: with no tty (piped install, CI) `read` fails and, under
    # `set -e`, would leave a half-finished install behind.
    r=n
    if [[ -t 0 ]]; then
        read -rp "   Download ggml-large-v3-turbo now? [y/N] " r || r=n
    else
        warn "No tty — skipping the download."
    fi
    if [[ "${r,,}" == y* ]]; then
        curl -L --progress-bar -o "$MODEL" "$MODEL_URL"
    else
        warn "Skipped. Fetch it later into $MODEL"
    fi
fi

# --- warm-up wav ---------------------------------------------------------
# 1 s of silence. Lets the service compile Vulkan shaders (~8 s) before your
# first real dictation instead of during it.
if [[ ! -f "$MODEL_DIR/warmup.wav" ]]; then
    if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -loglevel quiet -f lavfi -i anullsrc=r=16000:cl=mono \
               -t 1 "$MODEL_DIR/warmup.wav" </dev/null
        say "Generated warmup.wav"
    else
        warn "ffmpeg not found — skipping warmup.wav (the service handles its absence)"
    fi
fi

# --- systemd service -----------------------------------------------------
say "Installing the whisper-server user unit"
mkdir -p "$CFG_DIR/systemd/user"
install -m 644 "$SRC/systemd/whisper-server.service" "$CFG_DIR/systemd/user/whisper-server.service"
systemctl --user daemon-reload
if [[ -f "$MODEL" ]]; then
    systemctl --user enable --now whisper-server.service
    say "whisper-server enabled and started"
else
    warn "Service installed but not started: the model is missing."
    warn "Once you have it: systemctl --user enable --now whisper-server.service"
fi

cat <<'DONE'

Installed. One step left — bind a key in Hyprland:

  bind  = SUPER, G, exec, dictado start
  bindr = SUPER, G, exec, dictado stop

Hold the key while you speak, release to insert the text.
Full details and other config formats: see the README.
DONE
