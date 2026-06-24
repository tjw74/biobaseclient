#!/usr/bin/env bash
# Run on your MAC in Terminal — NOT inside the Parsec stream.
# Forces Parsec windowed + non-immersive so fullscreen trap cannot return.
set -euo pipefail

set_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i '' "s/^${key}=.*/${key}=${value}/" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

for DIR in "$HOME/Library/Application Support/Parsec" "$HOME/.parsec"; do
  mkdir -p "$DIR"
  TXT="$DIR/config.txt"
  JSON="$DIR/config.json"
  set_kv "$TXT" client_immersive 0
  set_kv "$TXT" client_windowed 1
  if [[ -f "$JSON" ]] && command -v python3 >/dev/null; then
    python3 - "$JSON" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    data = json.load(f)
data["client_immersive"] = 0
data["client_windowed"] = 1
with open(p, "w") as f:
    json.dump(data, f, indent=2)
PY
  fi
done

echo "Done: client_immersive=0 client_windowed=1"
echo "Quit Parsec (Cmd+Q), reopen, reconnect — stays windowed."
echo "While connected: Cmd+Shift+W window mode · Cmd+Shift+I immersive off"
