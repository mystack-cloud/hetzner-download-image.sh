#!/usr/bin/env bats
load test_helper
INSTALLER="${BATS_TEST_DIRNAME}/../get.hetzner-download-image.sh"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  echo '#!/bin/sh' > "$BATS_TEST_TMPDIR/payload.sh"
  mkdir -p "$BATS_TEST_TMPDIR/mockbin"
  cat > "$BATS_TEST_TMPDIR/mockbin/curl" <<EOS
#!/bin/sh
while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2;; *) shift;; esac; done
cp "$BATS_TEST_TMPDIR/payload.sh" "\$out"
EOS
  chmod +x "$BATS_TEST_TMPDIR/mockbin/curl"
  export PATH="$BATS_TEST_TMPDIR/mockbin:$PATH"
  export INSTALL_DEPS=0
}

@test "installs executable script into INSTALL_DIR" {
  INSTALL_DIR="$BATS_TEST_TMPDIR/bin" SKIP_PATH=1 run sh "$INSTALLER"
  [ "$status" -eq 0 ]
  [ -x "$BATS_TEST_TMPDIR/bin/hetzner-download-image.sh" ]
}

@test "adds PATH entry to .bashrc once" {
  touch "$HOME/.bashrc"
  export INSTALL_DIR="$BATS_TEST_TMPDIR/bin"
  sh "$INSTALLER"; sh "$INSTALLER"
  [ "$(grep -c '# hetzner-download-image.sh' "$HOME/.bashrc")" -eq 1 ]
  grep -q "$INSTALL_DIR" "$HOME/.bashrc"
}

@test "SKIP_PATH=1 leaves rc files untouched" {
  touch "$HOME/.bashrc"
  INSTALL_DIR="$BATS_TEST_TMPDIR/bin" SKIP_PATH=1 sh "$INSTALLER"
  [ ! -s "$HOME/.bashrc" ]
}
