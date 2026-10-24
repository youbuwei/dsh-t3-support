#!/usr/bin/env bash
set -euo pipefail

PROFILE="acp"
REMOVE=()
REMOVE_SHIM=0
REMOVE_ALL=0
BEGIN_MARKER="# >>> dsh-t3-support managed block >>>"
END_MARKER="# <<< dsh-t3-support managed block <<<"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/providers.yml"
SHIM_DST="$HOME/.local/bin/dsh-acp"

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--profile NAME] [--provider ID]... [--remove-shim] [--all]

Removes provider routes and/or the ACP stdout shim installed by dsh-t3-support.
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
      REMOVE+=("$2"); shift 2 ;;
    --remove-shim) REMOVE_SHIM=1; shift ;;
    --all) REMOVE_ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$REMOVE_ALL" -eq 1 ]]; then
  REMOVE=($(registry_ids))
  REMOVE_SHIM=1
fi

if [[ ${#REMOVE[@]} -eq 0 && "$REMOVE_SHIM" -eq 0 ]]; then
  usage >&2
  exit 2
fi

PATCH_FILE="$HOME/.dsh/profiles/$PROFILE/cordis.patch.yml"

if [[ -f "$PATCH_FILE" ]] && grep -qF "$BEGIN_MARKER" "$PATCH_FILE"; then
  BASE="$(mktemp)"
  trap 'rm -f "$BASE"' EXIT

  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { inblock = 1 }
    !inblock { print }
    $0 == end { inblock = 0 }
  ' "$PATCH_FILE" > "$BASE"

  CURRENT="$(awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { inblock = 1; next }
    $0 == end { inblock = 0 }
    inblock && /^      [A-Za-z0-9_.-]+:$/ { sub(/:$/, ""); sub(/^ +/, ""); print }
  ' "$PATCH_FILE")"

  KEEP=()
  for id in $(registry_ids); do
  route="$(registry_field "$id" route)"
  if grep -qx "$route" <<<"$CURRENT" && ! printf '%s\n' "${REMOVE[@]}" 2>/dev/null | grep -qx "$id"; then
      KEEP+=("$id")
    fi
  done

  if [[ ${#KEEP[@]} -gt 0 ]]; then
    {
      cat "$BASE"
      [[ -s "$BASE" && -n "$(tail -c 1 "$BASE")" ]] && echo
      echo "$BEGIN_MARKER"
      echo "# Model provider routes managed by dsh-t3-support. Do not edit."
      echo "- id: llm-pi-ai"
      echo "  config:"
      echo "    providers:"
      for id in "${KEEP[@]}"; do
        route="$(registry_field "$id" route)"
        env="$(registry_field "$id" apiKeyEnv)"
        name="$(registry_field "$id" displayName)"
        echo "      $route:"
        echo "        apiKeyEnv: $env"
        echo "        displayName: $name"
      done
      echo "$END_MARKER"
    } > "$PATCH_FILE"
    echo "providers kept: ${KEEP[*]}"
  else
    if ! grep -q '^-' "$BASE"; then printf '[]\n' >> "$BASE"; fi
    mv "$BASE" "$PATCH_FILE"; trap - EXIT
    echo "providers: none enabled"
  fi
elif [[ -f "$PATCH_FILE" ]]; then
  echo "providers: no managed block in $PATCH_FILE"
fi

if [[ "$REMOVE_SHIM" -eq 1 ]]; then
  if [[ -f "$SHIM_DST" ]]; then
    rm -f "$SHIM_DST"
    echo "shim     : removed $SHIM_DST"
  else
    echo "shim     : not installed"
  fi
fi
