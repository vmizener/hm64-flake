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

# shellcheck disable=SC2016
function fetch_asset() {
  local RELEASE_JSON=$1
  local SUFFIX=$2
  local QUERY='
    first(.assets[] | select(.name | test($suffix + "$"; "i"))) as $asset |
    {
      name: ($asset.name | sub($suffix + "$"; ""; "i")),
      version: .tag_name,
      asset: $asset.name,
      url: $asset.browser_download_url
    }
  '
  echo "$RELEASE_JSON" | jq -r --arg suffix "$SUFFIX" "$QUERY"
}

# shellcheck disable=SC2288
function get_latest_version() {
  local REPO=$1
  local -n _NAME=$2
  local -n _VERSION=$3
  local -n _ASSET=$4
  local -n _URL=$5
  local ADDRESS="repos/$REPO/releases/latest"
  local RELEASE_JSON
  if command -v gh &>/dev/null; then
    RELEASE_JSON=$(gh api "$ADDRESS")
  elif command -v , &>/dev/null; then
    RELEASE_JSON=$(, gh api "$ADDRESS")
  elif command -v curl &>/dev/null; then
    local AUTH_HEADERS=()
    [[ -n "${GH_TOKEN:-}" ]] && AUTH_HEADERS=(-H "Authorization: Bearer ${GH_TOKEN}")
    RELEASE_JSON=$(
      curl -sSL "${AUTH_HEADERS[@]}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/$ADDRESS"
    )
  else
    echo "Failed to get remote version: neither gh, ',', nor curl found" >&2
    exit 1
  fi

  local ASSETS
  ASSETS=$(echo "$RELEASE_JSON" | jq -r '.assets[].name')

  local INFO
  case "${ASSETS,,}" in
    *-linux.zip*)
      INFO=$(fetch_asset "$RELEASE_JSON" "-Linux\\.zip")
      ;;
    *.appimage*)
      INFO=$(fetch_asset "$RELEASE_JSON" "\\.appimage")
      ;;
    *)
      echo "Failed to find valid Linux release asset for $REPO" >&2
      exit 1
      ;;
  esac

  _NAME=$(echo "$INFO" | jq -r ".name")
  _VERSION=$(echo "$INFO" | jq -r ".version")
  _ASSET=$(echo "$INFO" | jq -r ".asset")
  _URL=$(echo "$INFO" | jq -r ".url")

  if [ -z "$_VERSION" ] || [ "$_VERSION" = "null" ] || [ -z "$_URL" ] || [ "$_URL" = "null" ]; then
    echo "Failed to find valid release version or Linux asset for $REPO" >&2
    exit 1
  fi
}

if [[ -n "$TARGET_PROJECT" ]]; then
  PROJECT_DIRS=("$REPO_ROOT/projects/$TARGET_PROJECT")
else
  PROJECT_DIRS=("$REPO_ROOT"/projects/*)
fi

UPDATES_JSON="[]"

for PROJECT_DIR in "${PROJECT_DIRS[@]}"; do
  [[ -d "$PROJECT_DIR" ]] || continue
  PROJECT_NAME=$(basename "$PROJECT_DIR")
  RELEASE_FILE="$PROJECT_DIR/release-linux.nix"

  REPO="" CURRENT_VERSION=""
  get_project_info "$PROJECT_DIR" REPO CURRENT_VERSION

  NAME="" VERSION="" ASSET="" URL=""
  get_latest_version "$REPO" NAME VERSION ASSET URL

  if [ "$VERSION" = "$CURRENT_VERSION" ]; then
    echo "$PROJECT_NAME is up-to-date (${CURRENT_VERSION})."
    continue
  fi

  echo "New release detected for $PROJECT_NAME: $VERSION ($NAME)"
  UPDATES_JSON=$(
    echo "$UPDATES_JSON" | jq -c \
      --arg project "$PROJECT_NAME" \
      --arg version "$VERSION" \
      --arg name "$NAME" \
      '. + [{project: $project, version: $version, name: $name}]'
  )

  if [[ "$CHECK_ONLY" == true ]]; then
    continue
  fi

  PREFETCH_FLAGS=(--type sha256)
  if [[ "${ASSET,,}" == *.zip ]]; then
    PREFETCH_FLAGS+=(--unpack)
  fi

  RAW_HASH=$(nix-prefetch-url "${PREFETCH_FLAGS[@]}" "$URL")
  SRI_HASH=$(nix hash convert --to sri "sha256:$RAW_HASH")

  cat <<EOF > "$RELEASE_FILE"
{
  name = "$NAME";
  version = "$VERSION";
  asset = "$ASSET";
  hash = "$SRI_HASH";
}
EOF

  nix fmt "$RELEASE_FILE"
  echo "Updated $RELEASE_FILE to $VERSION ($NAME)."
done

if [[ "$UPDATES_JSON" != "[]" ]]; then
  ci_output "has_update" "true"
else
  ci_output "has_update" "false"
fi
ci_output "updates" "$UPDATES_JSON"
