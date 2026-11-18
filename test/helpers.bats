#!/usr/bin/env bats
load test_helper
setup() { load_script; }

@test "get_host_arch maps uname -m values" {
  uname() { echo "$FAKE_M"; }
  for pair in x86_64:amd64 aarch64:arm64 arm64:arm64 armv7l:arm i686:386 ppc64le:ppc64le s390x:s390x riscv64:riscv64 weird:weird; do
    FAKE_M="${pair%%:*}"
    run get_host_arch
    [ "$output" = "${pair#*:}" ]
  done
}

@test "digest_to_name strips sha256: prefix" {
  [ "$(digest_to_name sha256:abc)" = abc ]
}

@test "default_output: gzip" {
  uname() { echo x86_64; }
  REPOSITORY=myorg/debian-13 REFERENCE=latest DO_GZIP=1
  [ "$(default_output)" = debian-13-amd64-latest.tar.gz ]
}

@test "default_output: no gzip, digest ref sanitized" {
  uname() { echo aarch64; }
  REPOSITORY=o/r REFERENCE=sha256:abc DO_GZIP=0
  [ "$(default_output)" = r-arm64-sha256_abc.tar ]
}

@test "get_manifest_digest_for_platform picks matching arch" {
  f="$BATS_TEST_TMPDIR/list.json"
  cat > "$f" <<'JSON'
{"manifests":[
 {"digest":"sha256:a","platform":{"architecture":"amd64","os":"linux"}},
 {"digest":"sha256:b","platform":{"architecture":"arm64","os":"linux"}},
 {"digest":"sha256:c","platform":{"architecture":"arm64","os":"windows"}}]}
JSON
  [ "$(get_manifest_digest_for_platform "$f" arm64)" = sha256:b ]
  [ "$(get_manifest_digest_for_platform "$f" amd64)" = sha256:a ]
}

@test "get_manifest_digest_for_platform falls back to first manifest" {
  f="$BATS_TEST_TMPDIR/list.json"
  echo '{"manifests":[{"digest":"sha256:z","platform":{"architecture":"amd64"}}]}' > "$f"
  [ "$(get_manifest_digest_for_platform "$f" s390x)" = sha256:z ]
}

@test "get_config_digest / get_layer_digests" {
  f="$BATS_TEST_TMPDIR/m.json"
  echo '{"config":{"digest":"sha256:c"},"layers":[{"digest":"sha256:1"},{"digest":"sha256:2"}]}' > "$f"
  [ "$(get_config_digest "$f")" = sha256:c ]
  [ "$(get_layer_digests "$f")" = "$(printf 'sha256:1\nsha256:2')" ]
}

@test "extract_layer_to_rootfs handles plain tar and skips dev/*" {
  d="$BATS_TEST_TMPDIR/x"; mkdir -p "$d/src/dev" "$d/src/etc" "$d/root1" "$d/root2"
  echo a > "$d/src/etc/f"; echo b > "$d/src/dev/n"
  ( cd "$d/src" && tar -cf ../plain.tar . && tar -czf ../gz.tar.gz . )
  extract_layer_to_rootfs "$d/plain.tar" "$d/root1"
  [ -f "$d/root1/etc/f" ]; [ ! -e "$d/root1/dev/n" ]
}

@test "extract_layer_to_rootfs handles gzip tar and skips dev/*" {
  d="$BATS_TEST_TMPDIR/x"; mkdir -p "$d/src/dev" "$d/src/etc" "$d/root"
  echo a > "$d/src/etc/f"; echo b > "$d/src/dev/n"
  ( cd "$d/src" && tar -czf ../gz.tar.gz . )
  extract_layer_to_rootfs "$d/gz.tar.gz" "$d/root"
  [ -f "$d/root/etc/f" ]; [ ! -e "$d/root/dev/n" ]
}
