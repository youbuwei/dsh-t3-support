#!/usr/bin/env bash
set -euo pipefail

PROFILE="acp"
BEGIN_MARKER="# >>> dsh-glm-provider managed block >>>"
END_MARKER="# <<< dsh-glm-provider managed block <<<"

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--profile NAME]

Removes the dsh-glm-provider managed block from a profile's cordis.patch.yml.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "error: --profile needs a value" >&2; exit 2; }
      PROFILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

PATCH_FILE="$HOME/.dsh/profiles/$PROFILE/cordis.patch.yml"

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "nothing to uninstall: $PATCH_FILE does not exist" >&2
  exit 0
fi

if ! grep -qF "$BEGIN_MARKER" "$PATCH_FILE"; then
  echo "nothing to uninstall: no managed block in $PATCH_FILE"
  exit 0
fi

BASE="$(mktemp)"
trap 'rm -f "$BASE"' EXIT

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
  $0 == begin { inblock = 1 }
  !inblock { print }
  $0 == end { inblock = 0 }
' "$PATCH_FILE" > "$BASE"

# Comments alone are not a YAML document; keep a valid empty array when the
# managed block was the only content.
if ! grep -q '^-' "$BASE"; then
  printf '[]\n' >> "$BASE"
fi

mv "$BASE" "$PATCH_FILE"
trap - EXIT
echo "uninstalled: $PATCH_FILE"
