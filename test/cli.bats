#!/usr/bin/env bats
load test_helper

setup() {
  setup_mock_registry
  export TMPDIR="$BATS_TEST_TMPDIR"
  export OUT="$BATS_TEST_TMPDIR/out"
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--version prints semantic version" {
  run "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^hetzner-download-image\.sh\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "no arguments fails with usage" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "unknown option fails" {
  run "$SCRIPT" --bogus img
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "output given as a file path is rejected" {
  run "$SCRIPT" -o foo.tar.gz alpine
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be a directory"* ]]
}

@test "missing dependency is reported" {
  d="$BATS_TEST_TMPDIR/nojq"; mkdir "$d"
  for c in curl tar sed grep head tr cat; do ln -s "$(command -v $c)" "$d/$c"; done
  PATH="$d" run /bin/sh "$SCRIPT" alpine
  [ "$status" -ne 0 ]
  [[ "$output" == *"required command not found: jq"* ]]
}

@test "downloads and merges layers into a gzip rootfs" {
  make_image myorg/debian-13 latest
  run "$SCRIPT" -q -o "$OUT" ghcr.io/myorg/debian-13:latest
  [ "$status" -eq 0 ]
  f=$(ls "$OUT"/debian-13-*-latest.tar.gz)
  [ -f "$f" ]
  list=$(tar -tzf "$f")
  [[ "$list" == *"etc/os-release"* ]]
  [[ "$list" == *"usr/bin/tool"* ]]
  [[ "$list" != *"dev/null-file"* ]]
  [ "$(tar -xzOf "$f" ./etc/os-release)" = overridden ]
}

@test "--no-gzip writes a plain tar" {
  make_image myorg/debian-13 latest
  run "$SCRIPT" -q --no-gzip -o "$OUT" ghcr.io/myorg/debian-13:latest
  [ "$status" -eq 0 ]
  f=$(ls "$OUT"/debian-13-*-latest.tar)
  tar -tf "$f" >/dev/null
}

@test "positional OUTPUT_DIR is honored and created" {
  make_image myorg/debian-13 v2
  run "$SCRIPT" -q ghcr.io/myorg/debian-13:v2 "$OUT/nested"
  [ "$status" -eq 0 ]
  ls "$OUT"/nested/debian-13-*-v2.tar.gz
}

@test "manifest list resolves to platform manifest" {
  make_image myorg/multi sha256:child
  r="$MOCK_REGISTRY_DIR"; p="v2__myorg__multi"
  arch=$(HETZNER_DOWNLOAD_IMAGE_SOURCE_ONLY=1 sh -c ". '$SCRIPT'; get_host_arch")
  cat > "$r/${p}__manifests__latest" <<JSON
{"manifests":[{"digest":"sha256:child","platform":{"architecture":"$arch","os":"linux"}}]}
JSON
  run "$SCRIPT" -q -o "$OUT" ghcr.io/myorg/multi:latest
  [ "$status" -eq 0 ]
  ls "$OUT"/multi-*-latest.tar.gz
}

@test "unknown image reports registry error" {
  run "$SCRIPT" -o "$OUT" ghcr.io/nope/missing:latest
  [ "$status" -ne 0 ]
  [[ "$output" == *"NAME_UNKNOWN"* ]]
}

@test "temporary work dir is cleaned up" {
  make_image myorg/debian-13 latest
  "$SCRIPT" -q -o "$OUT" ghcr.io/myorg/debian-13:latest
  [ -z "$(ls -d "$BATS_TEST_TMPDIR"/hetzner-download-image.* 2>/dev/null)" ]
}
