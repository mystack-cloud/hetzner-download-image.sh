#!/bin/sh
# hetzner-download-image.sh - Download a container image as a plain rootfs tarball for Hetzner installimage
# OCI/Docker Registry API in pure shell (curl + jq). Output: single rootfs .tar[.gz] (top-level bin, etc, usr, ...).
#
# Usage:
#   hetzner-download-image.sh [OPTIONS] IMAGE [OUTPUT.tar.gz]
#   hetzner-download-image.sh -h | --help
#
# Options:
#   -o, --output FILE   Output path (default: <repo>_<tag>.tar.gz)
#   --no-gzip           Write uncompressed .tar
#   -u, --user USER[:PASSWORD]   Registry credentials (required for private images)
#   -q, --quiet         Less output
#   -h, --help          Show help

set -e

ME="${0##*/}"

# --- Dependencies ---
for cmd in curl jq tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$ME: required command not found: $cmd" >&2
    exit 1
  fi
done

# --- Defaults and state ---
REGISTRY=""
REPOSITORY=""
REFERENCE=""
IMAGE_REF=""
OUTPUT_FILE=""
DO_GZIP=1
QUIET=0
REG_USER=""
REG_PASS=""
REGISTRY_TOKEN_FILE=""
TMPDIR="${TMPDIR:-/tmp}"
WORKDIR=""

# --- Help ---
show_help() {
  sed -n '2,18p' "$0" | sed 's/^# \?//'
  echo "Examples:"
  echo "  $ME ghcr.io/myorg/hetzner-images/debian-13:latest"
  echo "  $ME -o /root/local_images/debian-13.tar.gz -u user:token ghcr.io/myorg/debian-13:latest"
  echo "Install: curl https://get.hetzner-download-image.sh | sh -s"
  exit 0
}

log() { [ "$QUIET" = 1 ] || echo "$@"; }
log_err() { echo "$ME: $*" >&2; }

# --- Parse image reference [registry/]repository[:tag|@digest] ---
parse_image() {
  local img="$1"
  local rest=""
  IMAGE_REF="$img"

  case "$img" in
    *@sha256:*)
      rest="${img#*@sha256:}"
      REFERENCE="sha256:${rest}"
      img="${img%%@sha256:*}"
      ;;
    *:*)
      rest="${img#*:}"
      case "$img" in
        */*) REFERENCE="${img##*:}"; img="${img%:*}" ;;
        *)   REFERENCE="$rest"; img="${img%%:*}" ;;
      esac
      ;;
    *)
      REFERENCE="latest"
      ;;
  esac

  [ -n "$img" ] || { log_err "invalid image: $IMAGE_REF"; exit 1; }

  case "$img" in
    */*/*) REGISTRY="${img%%/*}"; REPOSITORY="${img#*/}" ;;
    */*)
      case "$img" in
        *.*.*|*:*) REGISTRY="${img%%/*}"; REPOSITORY="${img#*/}" ;;
        *) REGISTRY=""; REPOSITORY="$img" ;;
      esac
      ;;
    *) REPOSITORY="$img"; REGISTRY="" ;;
  esac

  if [ -z "$REGISTRY" ] || [ "$REGISTRY" = "docker.io" ]; then
    REGISTRY="registry-1.docker.io"
    case "$REPOSITORY" in */*) ;; *) REPOSITORY="library/$REPOSITORY" ;; esac
  fi
  [ -n "$REFERENCE" ] || REFERENCE="latest"
}

registry_base() { echo "https://${REGISTRY}"; }

# --- Bearer token ---
get_bearer_token() {
  local headers_file="$1"
  local token_file="$2"
  local auth_header realm service scope url resp_file

  auth_header=$(grep -i 'www-authenticate' "$headers_file" 2>/dev/null | head -1 | sed 's/^[^:]*: *//i' | tr -d '\r')
  [ -n "$auth_header" ] || return 0

  realm=$(echo "$auth_header" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')
  service=$(echo "$auth_header" | sed -n 's/.*service="\([^"]*\)".*/\1/p')
  scope=$(echo "$auth_header" | sed -n 's/.*scope="\([^"]*\)".*/\1/p')
  [ -n "$realm" ] || return 0

  url="$realm?service=${service}&scope=${scope}"
  resp_file="${TMPDIR:-/tmp}/registry_token_resp.$$.json"
  curl --silent --show-error ${REG_USER:+-u "$REG_USER:$REG_PASS"} "$url" -o "$resp_file" 2>/dev/null || true
  if [ -n "$token_file" ] && [ -s "$resp_file" ]; then
    jq -r '.token // .access_token // empty' "$resp_file" > "$token_file"
  fi
  rm -f "$resp_file" 2>/dev/null || true
}

# --- GET with optional Bearer auth ---
registry_get() {
  local path="$1"; shift
  local base url headers_file body_file
  base=$(registry_base)
  url="${base}/v2/${REPOSITORY}/${path}"
  headers_file="${WORKDIR}/headers.$$"
  body_file="${WORKDIR}/body.$$"

  _do_get() {
    local opts="--silent --show-error --location -D $headers_file -o $body_file"
    if [ -n "$REGISTRY_TOKEN_FILE" ] && [ -s "$REGISTRY_TOKEN_FILE" ]; then
      printf 'Authorization: Bearer ' > "${WORKDIR}/.auth_header"
      tr -d '\n\r' < "$REGISTRY_TOKEN_FILE" >> "${WORKDIR}/.auth_header"
      curl $opts -H "@${WORKDIR}/.auth_header" "$@" "$url" 2>/dev/null || true
    else
      curl $opts "$@" "$url" 2>/dev/null || true
    fi
  }

  _do_get
  if grep -qi 'www-authenticate' "$headers_file" 2>/dev/null; then
    get_bearer_token "$headers_file" "${WORKDIR}/.token"
    if [ -f "${WORKDIR}/.token" ] && [ -s "${WORKDIR}/.token" ]; then
      REGISTRY_TOKEN_FILE="${WORKDIR}/.token"
      _do_get "$@"
    fi
  fi
  cat "$body_file" 2>/dev/null || true
}

get_config_digest() { jq -r '.config.digest // empty' "$1"; }
get_layer_digests() { jq -r '.layers[]? | .digest' "$1"; }
get_manifest_list_digest() { jq -r '.manifests[0].digest // empty' "$1"; }
digest_to_name() { echo "$1" | sed 's/^sha256://'; }

# Extract layer (plain tar or gzip) into rootfs dir.
# Exclude ./dev/* so we never mknod (requires root); target system creates /dev at boot.
extract_layer_to_rootfs() {
  local layer_file="$1" rootfs_dir="$2"
  ( gzip -dc "$layer_file" 2>/dev/null || cat "$layer_file" ) | ( cd "$rootfs_dir" && tar -xf - --exclude='dev/*' )
}

# --- Default output ---
default_output() {
  local base
  base=$(echo "${REPOSITORY}/${REFERENCE}" | tr '/:' '__')
  echo "${base}.tar"
}

# ========== DOWNLOAD (rootfs only) ==========
cmd_download() {
  local manifest_file config_digest config_name layer_name manifest_path
  local layers_dir rootfs_dir

  WORKDIR=$(mktemp -d "${TMPDIR}/hetzner-download-image.XXXXXX")
  trap 'rm -rf "$WORKDIR"' EXIT

  case "$OUTPUT_FILE" in */*) mkdir -p "${OUTPUT_FILE%/*}" ;; esac

  manifest_file="${WORKDIR}/manifest.json"
  manifest_path="manifests/${REFERENCE}"
  log "Pulling ${IMAGE_REF} from ${REGISTRY}..."

  registry_get "$manifest_path" \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.oci.image.index.v1+json' > "$manifest_file" || true

  if jq -e '.errors != null' "$manifest_file" >/dev/null 2>&1; then
    _code=$(jq -r '.errors[0].code // "UNKNOWN"' "$manifest_file")
    _msg=$(jq -r '.errors[0].message // ""' "$manifest_file")
    log_err "manifest fetch failed: ${_code}${_msg:+ ($_msg)}"
    case "$_code" in
      UNAUTHORIZED) log_err "use -u USER:TOKEN for private images (e.g. -u USER:ghp_... for GitHub)" ;;
      NAME_UNKNOWN) log_err "check image name and tag (e.g. replace myorg with your org)" ;;
    esac
    exit 1
  fi
  if ! [ -s "$manifest_file" ]; then
    log_err "failed to fetch manifest for ${REPOSITORY}:${REFERENCE}"
    exit 1
  fi

  if jq -e '.manifests != null' "$manifest_file" >/dev/null 2>&1; then
    local list_digest
    list_digest=$(get_manifest_list_digest "$manifest_file")
    [ -n "$list_digest" ] || { log_err "could not get digest from manifest list"; exit 1; }
    log "Resolving multi-arch image to digest ${list_digest}..."
    registry_get "manifests/${list_digest}" \
      -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
      -H 'Accept: application/vnd.oci.image.manifest.v1+json' > "$manifest_file" || true
    if ! [ -s "$manifest_file" ] || jq -e '.errors != null' "$manifest_file" >/dev/null 2>&1; then
      log_err "failed to fetch image manifest"
      exit 1
    fi
  fi

  config_digest=$(get_config_digest "$manifest_file")
  [ -n "$config_digest" ] || { log_err "could not parse config digest"; exit 1; }
  config_name=$(digest_to_name "$config_digest")
  log "Fetching config ${config_digest}..."
  registry_get "blobs/${config_digest}" > "${WORKDIR}/${config_name}.json"
  [ -s "${WORKDIR}/${config_name}.json" ] || { log_err "failed to fetch config blob"; exit 1; }

  layers_dir="${WORKDIR}/layers"
  mkdir -p "$layers_dir"
  get_layer_digests "$manifest_file" > "${WORKDIR}/layer_list"
  local count=0
  while read -r layer_digest; do
    [ -z "$layer_digest" ] && continue
    count=$((count + 1))
    layer_name=$(digest_to_name "$layer_digest")
    mkdir -p "${layers_dir}/${layer_name}"
    log "Fetching layer $count ${layer_digest}..."
    registry_get "blobs/${layer_digest}" > "${layers_dir}/${layer_name}/layer.tar"
    [ -s "${layers_dir}/${layer_name}/layer.tar" ] || { log_err "failed to fetch layer ${layer_digest}"; exit 1; }
  done < "${WORKDIR}/layer_list"

  rootfs_dir="${WORKDIR}/rootfs"
  mkdir -p "$rootfs_dir"
  log "Building rootfs from layers..."
  while read -r layer_digest; do
    [ -z "$layer_digest" ] && continue
    layer_name=$(digest_to_name "$layer_digest")
    extract_layer_to_rootfs "${layers_dir}/${layer_name}/layer.tar" "$rootfs_dir"
  done < "${WORKDIR}/layer_list"

  log "Writing rootfs to ${OUTPUT_FILE}..."
  ( cd "$rootfs_dir" && tar -cf - . ) > "${WORKDIR}/out.tar"
  if [ "$DO_GZIP" = 1 ]; then
    gzip -c "${WORKDIR}/out.tar" > "${OUTPUT_FILE}"
    log "Created ${OUTPUT_FILE}"
  else
    mv "${WORKDIR}/out.tar" "${OUTPUT_FILE}"
    log "Created ${OUTPUT_FILE}"
  fi
}

# --- Main ---
COMMAND=""
while [ $# -gt 0 ]; do
  case "$1" in
    -u|--user)
      REG_USER="${2:-}"
      REG_PASS="${REG_USER#*:}"
      [ "$REG_PASS" = "$REG_USER" ] && REG_PASS=""
      REG_USER="${REG_USER%%:*}"
      shift 2
      ;;
    -q|--quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      show_help
      ;;
    -o|--output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --no-gzip)
      DO_GZIP=0
      shift
      ;;
    -*)
      log_err "unknown option: $1"
      exit 1
      ;;
    *)
      if [ -z "$IMAGE_REF" ]; then
        parse_image "$1"
        shift
        [ $# -gt 0 ] && [ "${1#-}" = "$1" ] && OUTPUT_FILE="$1" && shift
      else
        [ "${1#-}" = "$1" ] && OUTPUT_FILE="$1"
        shift
      fi
      ;;
  esac
done

[ -n "$IMAGE_REF" ] || { log_err "usage: $ME [OPTIONS] IMAGE [OUTPUT]"; exit 1; }
[ -n "$OUTPUT_FILE" ] || OUTPUT_FILE=$(default_output)
if [ "$DO_GZIP" = 1 ] && [ "${OUTPUT_FILE%.gz}" = "$OUTPUT_FILE" ]; then
  [ "${OUTPUT_FILE%.tar}" = "$OUTPUT_FILE" ] && OUTPUT_FILE="${OUTPUT_FILE}.tar"
fi

cmd_download
