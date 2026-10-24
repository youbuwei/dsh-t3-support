#!/usr/bin/env bash
set -euo pipefail

PROFILE="acp"
ENV_NAME="ZAI_CODING_CN_API_KEY"
FORCE=0

BEGIN_MARKER="# >>> dsh-glm-provider managed block >>>"
END_MARKER="# <<< dsh-glm-provider managed block <<<"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--profile NAME] [--env KEY] [--force]

Adds the GLM Coding Plan provider route (zai-coding-cn) to a dsh profile's
cordis.patch.yml as a managed, removable block.

Options:
  --profile NAME  dsh profile to patch (default: acp)
  --env KEY       credential/env name for the API key
                  (default: ZAI_CODING_CN_API_KEY)
  --force         allow installing beside a manual llm-pi-ai patch
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "error: --profile needs a value" >&2; exit 2; }
      PROFILE="$2"; shift 2 ;;
    --env)
      [[ $# -ge 2 ]] || { echo "error: --env needs a value" >&2; exit 2; }
      ENV_NAME="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

PROFILE_DIR="$HOME/.dsh/profiles/$PROFILE"
PATCH_FILE="$PROFILE_DIR/cordis.patch.yml"

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "error: profile '$PROFILE' not found at $PROFILE_DIR" >&2
  echo "hint: boot it once first, e.g. dsh --profile $PROFILE --help" >&2
  exit 1
fi

if [[ ! -f "$PATCH_FILE" ]]; then
  printf '[]\n' > "$PATCH_FILE"
fi

BASE="$(mktemp)"
trap 'rm -f "$BASE"' EXIT

# Drop any previous managed block, then drop lone [] placeholders so the
# appended sequence items keep the file a single valid YAML array.
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

{
  cat "$BASE"
  [[ -s "$BASE" ]] && [[ "$(tail -c 1 "$BASE")" != "" ]] && echo
  echo "$BEGIN_MARKER"
  echo "# GLM Coding Plan models via the zai-coding-cn route."
  echo "# Auth resolves from the dsh credential named by apiKeyEnv."
  echo "- id: llm-pi-ai"
  echo "  config:"
  echo "    providers:"
  echo "      zai-coding-cn:"
  echo "        apiKeyEnv: $ENV_NAME"
  echo "        displayName: GLM Coding Plan"
  echo "$END_MARKER"
} > "$PATCH_FILE"

echo "installed: $PATCH_FILE"
echo "provider : zai-coding-cn (apiKeyEnv: $ENV_NAME)"

if command -v dsh >/dev/null 2>&1; then
  if dsh --profile "$PROFILE" --dump-config 2>/dev/null | grep -q 'zai-coding-cn'; then
    echo "validate : OK (zai-coding-cn present in composed config)"
  else
    echo "warning : dsh did not report zai-coding-cn; inspect $PATCH_FILE" >&2
  fi
fi
