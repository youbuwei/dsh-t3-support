#!/usr/bin/env bash
set -euo pipefail

PROFILE="acp"
FORCE=0
WITH_SHIM=0
REQUESTED=()
BEGIN_MARKER="# >>> dsh-t3-support managed block >>>"
END_MARKER="# <<< dsh-t3-support managed block <<<"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/providers.yml"
SHIM_SRC="$SCRIPT_DIR/bin/dsh-acp"
SHIM_DST="$HOME/.local/bin/dsh-acp"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--profile NAME] [--provider ID]... [--with-shim] [--force]

Enables model provider routes and/or the ACP stdout shim for a dsh profile.

Options:
  --profile NAME  dsh profile to patch (default: acp)
  --provider ID   enable a provider from providers.yml (repeatable)
  --with-shim     install bin/dsh-acp to ~/.local/bin
  --list-providers
  --force         allow installing beside a manual llm-pi-ai patch
EOF
}

registry_field() {
  local id="$1" field="$2"
  awk -v id="$id" -v field="$field" '
    /^[^ #]/ { in_entry = ($1 == id":") }
    in_entry && $1 == field":" { sub(/^[^:]*:[ ]*/, ""); print; exit }
  ' "$REGISTRY"
}

registry_ids() {
  awk '/^[^ #]/ { sub(/:$/, "", $1); print $1 }' "$REGISTRY"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "error: --profile needs a value" >&2; exit 2; }
      PROFILE="$2"; shift 2 ;;
    --provider)
      [[ $# -ge 2 ]] || { echo "error: --provider needs a value" >&2; exit 2; }
      REQUESTED+=("$2"); shift 2 ;;
    --with-shim) WITH_SHIM=1; shift ;;
    --list-providers)
      registry_ids; exit 0 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -f "$REGISTRY" ]]; then
  echo "error: registry not found: $REGISTRY" >&2; exit 1
fi

for id in "${REQUESTED[@]}"; do
  [[ -n "$(registry_field "$id" route)" ]] || {
    echo "error: unknown provider '$id' in providers.yml" >&2
    echo "hint: ./install.sh --list-providers" >&2
    exit 1
  }
done

PROFILE_DIR="$HOME/.dsh/profiles/$PROFILE"
PATCH_FILE="$PROFILE_DIR/cordis.patch.yml"

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "error: profile '$PROFILE' not found at $PROFILE_DIR" >&2
  echo "hint: boot it once first, e.g. dsh --profile $PROFILE --help" >&2
  exit 1
fi

[[ -f "$PATCH_FILE" ]] || printf '[]\n' > "$PATCH_FILE"

BASE="$(mktemp)"
trap 'rm -f "$BASE"' EXIT

# Strip our block, then drop lone [] placeholders so the regenerated file
# stays one valid top-level YAML array.
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
  $0 == begin { inblock = 1 }
  !inblock { print }
  $0 == end { inblock = 0 }
' "$PATCH_FILE" | grep -v '^\[\]$' > "$BASE" || true

if grep -q 'id: llm-pi-ai' "$BASE" && [[ "$FORCE" -eq 0 ]]; then
  echo "error: $PATCH_FILE already has an llm-pi-ai patch outside this plugin's block" >&2
  echo "hint: remove it, or rerun with --force" >&2
  exit 1
fi

# Current routes = keys under providers: inside our previous block.
CURRENT="$(awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
  $0 == begin { inblock = 1; next }
  $0 == end { inblock = 0 }
  inblock && /^      [A-Za-z0-9_.-]+:$/ { sub(/:$/, ""); sub(/^ +/, ""); print }
' "$PATCH_FILE")"

# Union of current + requested, in registry order for deterministic output.
ENABLED=()
for id in $(registry_ids); do
  route="$(registry_field "$id" route)"
  if grep -qx "$route" <<<"$CURRENT" || printf '%s\n' "${REQUESTED[@]}" | grep -qx "$id"; then
    ENABLED+=("$id")
  fi
done

if [[ ${#ENABLED[@]} -gt 0 ]]; then
  {
    cat "$BASE"
    [[ -s "$BASE" && -n "$(tail -c 1 "$BASE")" ]] && echo
    echo "$BEGIN_MARKER"
    echo "# Model provider routes managed by dsh-t3-support. Do not edit."
    echo "- id: llm-pi-ai"
    echo "  config:"
    echo "    providers:"
    for id in "${ENABLED[@]}"; do
      route="$(registry_field "$id" route)"
      env="$(registry_field "$id" apiKeyEnv)"
      name="$(registry_field "$id" displayName)"
      echo "      $route:"
      echo "        apiKeyEnv: $env"
      echo "        displayName: $name"
    done
    echo "$END_MARKER"
  } > "$PATCH_FILE"
  echo "providers: ${ENABLED[*]} -> $PATCH_FILE"
else
  mv "$BASE" "$PATCH_FILE"; trap - EXIT
  echo "providers: none enabled"
fi

if [[ "$WITH_SHIM" -eq 1 ]]; then
  mkdir -p "$(dirname "$SHIM_DST")"
  cp "$SHIM_SRC" "$SHIM_DST"
  chmod +x "$SHIM_DST"
  echo "shim     : installed $SHIM_DST"
  case ":$PATH:" in
    *":$(dirname "$SHIM_DST"):"*) ;;
    *) echo "warning : $(dirname "$SHIM_DST") is not on PATH" >&2 ;;
  esac
fi

if command -v dsh >/dev/null 2>&1; then
  ok=1
  for id in "${ENABLED[@]}"; do
    route="$(registry_field "$id" route)"
    if dsh --profile "$PROFILE" --dump-config 2>/dev/null | grep -q "$route"; then
      echo "validate : $route OK"
    else
      echo "validate : $route MISSING" >&2; ok=0
    fi
  done
  [[ "$ok" -eq 1 ]] || exit 1
fi
