# Shared helpers for bats tests.
SCRIPT="${BATS_TEST_DIRNAME}/../hetzner-download-image.sh"

# Source the script's functions without running main.
load_script() {
  export HETZNER_DOWNLOAD_IMAGE_SOURCE_ONLY=1
  # shellcheck disable=SC1090
  . "$SCRIPT"
}

# Put the mock curl first in PATH and create an empty mock registry.
setup_mock_registry() {
  export MOCK_REGISTRY_DIR="${BATS_TEST_TMPDIR}/registry"
  export MOCK_CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  mkdir -p "$MOCK_REGISTRY_DIR"
  : > "$MOCK_CURL_LOG"
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
}

# make_image REPO TAG : serves a two-layer image (plain tar + gzip tar; layer 2 overrides etc/os-release)
make_image() {
  local repo="$1" tag="$2" d="${BATS_TEST_TMPDIR}/build"
  mkdir -p "$d/l1/etc" "$d/l1/dev" "$d/l1/usr/bin" "$d/l2/etc"
  echo "base" > "$d/l1/etc/os-release"
  echo "x" > "$d/l1/dev/null-file"
  echo "bin" > "$d/l1/usr/bin/tool"
  echo "overridden" > "$d/l2/etc/os-release"
  ( cd "$d/l1" && tar -cf ../l1.tar . )
  ( cd "$d/l2" && tar -cf - . | gzip -c > ../l2.tar.gz )
  local r="$MOCK_REGISTRY_DIR" p="v2__${repo//\//__}"
  cp "$d/l1.tar" "$r/${p}__blobs__sha256:l1"
  cp "$d/l2.tar.gz" "$r/${p}__blobs__sha256:l2"
  echo '{"os":"linux"}' > "$r/${p}__blobs__sha256:cfg"
  cat > "$r/${p}__manifests__${tag}" <<JSON
{"schemaVersion":2,"config":{"digest":"sha256:cfg"},
 "layers":[{"digest":"sha256:l1"},{"digest":"sha256:l2"}]}
JSON
}
