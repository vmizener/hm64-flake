#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECK_ONLY=false
TARGET_PROJECT=""

for arg in "$@"; do
  case "$arg" in
    --check-only)
      CHECK_ONLY=true
      ;;
    *)
      TARGET_PROJECT="$arg"
      ;;
  esac
done

function ci_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$1=$2" >> "$GITHUB_OUTPUT"
  fi
}

function get_project_info() {
  local PROJECT_DIR=$1
  local -n _REPO=$2
  local -n _CURRENT_VERSION=$3

  if command -v nix &>/dev/null; then
    local PROJECT_META
    PROJECT_META=$(
      nix eval --impure --json --expr \
        "let p = import \"$PROJECT_DIR\"; in { inherit (p) repo; inherit (p.releaseInfo) version; }"
    )
    _REPO=$(echo "$PROJECT_META" | jq -r '.repo')
    _CURRENT_VERSION=$(echo "$PROJECT_META" | jq -r '.version')
  else
    _REPO=$(sed -n 's/.*repo = "\([^"]*\)".*/\1/p' "$PROJECT_DIR/default.nix")
    _CURRENT_VERSION=$(sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$PROJECT_DIR/release-linux.nix")
  fi
}

# shellcheck disable=SC2016,SC2288
function get_latest_version() {
  local REPO=$1
  local -n _NAME=$2
  local -n _VERSION=$3
  local -n _URL=$4
  local ADDRESS="repos/$REPO/releases/latest"
  local QUERY='
    first(.assets[] | select(.name | endswith("-Linux.zip"))) as $asset |
    {
      name: ($asset.name | sub("-Linux\\.zip$"; "")),
      version: .tag_name,
      url: $asset.browser_download_url
    }
  '
  local INFO
  if command -v gh &>/dev/null; then
    INFO=$(gh api "$ADDRESS" | jq -r "$QUERY")
  elif command -v , &>/dev/null; then
    INFO=$(, gh api "$ADDRESS" | jq -r "$QUERY")
  elif command -v curl &>/dev/null; then
    local AUTH_HEADERS=()
    [[ -n "${GH_TOKEN:-}" ]] && AUTH_HEADERS=(-H "Authorization: Bearer ${GH_TOKEN}")
    INFO=$(
      curl -sSL "${AUTH_HEADERS[@]}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/$ADDRESS" \
      | jq -r "$QUERY"
    )
  else
    echo "Failed to get remote version: neither gh, ',', nor curl found" >&2
    exit 1
  fi

  _NAME=$(echo "$INFO" | jq -r ".name")
  _VERSION=$(echo "$INFO" | jq -r ".version")
  _URL=$(echo "$INFO" | jq -r ".url")

  if [ -z "$_VERSION" ] || [ "$_VERSION" = "null" ] || [ -z "$_URL" ] || [ "$_URL" = "null" ]; then
    echo "Failed to find valid release version or Linux zip asset for $REPO" >&2
    exit 1
  fi
}

if [[ -n "$TARGET_PROJECT" ]]; then
  PROJECT_DIRS=("$REPO_ROOT/projects/$TARGET_PROJECT")
else
  PROJECT_DIRS=("$REPO_ROOT"/projects/*)
fi

ANY_UPDATE=false

for PROJECT_DIR in "${PROJECT_DIRS[@]}"; do
  [[ -d "$PROJECT_DIR" ]] || continue
  PROJECT_NAME=$(basename "$PROJECT_DIR")
  RELEASE_FILE="$PROJECT_DIR/release-linux.nix"

  REPO="" CURRENT_VERSION=""
  get_project_info "$PROJECT_DIR" REPO CURRENT_VERSION

  NAME="" VERSION="" URL=""
  get_latest_version "$REPO" NAME VERSION URL

  if [ "$VERSION" = "$CURRENT_VERSION" ]; then
    echo "$PROJECT_NAME is up-to-date (${CURRENT_VERSION})."
    continue
  fi

  echo "New release detected for $PROJECT_NAME: $VERSION ($NAME)"
  ANY_UPDATE=true
  ci_output "has_update" "true"
  ci_output "version" "$VERSION"
  ci_output "name" "$NAME"

  if [[ "$CHECK_ONLY" == true ]]; then
    continue
  fi

  RAW_HASH=$(nix-prefetch-url --unpack --type sha256 "$URL")
  SRI_HASH=$(nix hash convert --to sri "sha256:$RAW_HASH")

  cat <<EOF > "$RELEASE_FILE"
{
  name = "$NAME";
  version = "$VERSION";
  hash = "$SRI_HASH";
}
EOF

  nix fmt "$RELEASE_FILE"
  echo "Updated $RELEASE_FILE to $VERSION ($NAME)."
done

if [[ "$ANY_UPDATE" == false ]]; then
  ci_output "has_update" "false"
fi
