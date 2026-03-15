# hetzner-download-image.sh

**Download a container image as a plain rootfs tarball for Hetzner installimage.**

Pure shell (curl + jq). Fetches from OCI/Docker registries and outputs a single `.tar[.gz]` with top-level `bin`, `etc`, `usr`, `root` — the format [Hetzner installimage](https://docs.hetzner.com/robot/dedicated-server/operating-systems/installimage/) expects. No Docker daemon required.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/mystack-cloud/hetzner-download-image.sh/main/get.hetzner-download-image.sh | sh -s
```

Or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/mystack-cloud/hetzner-download-image.sh/main/get.hetzner-download-image.sh | sh -s
```

This installs `hetzner-download-image.sh` into `~/.local/bin` and adds it to PATH. To skip modifying your shell config:

```bash
SKIP_PATH=1 curl https://get.hetzner-download-image.sh | sh -s
```

Override install directory:

```bash
INSTALL_DIR=/usr/local/bin curl https://get.hetzner-download-image.sh | sh -s
```

Install from a specific URL (e.g. GitHub raw):

```bash
SCRIPT_URL=https://raw.githubusercontent.com/OWNER/REPO/main/hetzner-download-image.sh curl https://get.hetzner-download-image.sh | sh -s
```

## Requirements

- **curl** – HTTP
- **jq** – JSON
- **tar** – archives
- **gzip** – optional (for `.tar.gz` output)

## Usage

```bash
hetzner-download-image.sh [OPTIONS] IMAGE [OUTPUT_DIR]

# Examples
hetzner-download-image.sh ghcr.io/myorg/hetzner-images/debian-13:latest
hetzner-download-image.sh -o /root/local_images -u user:token ghcr.io/myorg/debian-13:latest
hetzner-download-image.sh --no-gzip -o ./images docker.io/library/alpine:3.19
```

| Option       | Description |
|-------------|-------------|
| `-o DIR`    | Output directory (default: current dir). Filename is always `<name>-<tag>-<arch>.tar[.gz]` where `<name>` is the last path component of the image repo (e.g. `debian-13-latest-amd64.tar.gz`) |
| `--no-gzip` | Write uncompressed `.tar` |
| `-u USER[:PASSWORD]` | Registry credentials (required for private images) |
| `-q`        | Quiet |
| `-h`, `--help` | Show help |

The script writes a single rootfs tarball into the output directory. The file name is derived from the image (last repo path component + tag) and **host architecture** (e.g. `debian-13-latest-amd64.tar.gz` by default, or `debian-13-latest-amd64.tar` with `--no-gzip`). Point installimage’s config at this file (e.g. in `config.cfg`).

## Image reference

- `[REGISTRY/]REPOSITORY[:TAG|@sha256:DIGEST]`
- Default registry: Docker Hub (`registry-1.docker.io`)
- Default tag: `latest`
- For GitHub Container Registry use `-u USER:ghp_TOKEN` or `GITHUB_TOKEN`.

## Architecture

For multi-arch images (manifest lists), the script picks the manifest matching the **host** architecture (`uname -m` → OCI: amd64, arm64, arm, 386, ppc64le, s390x, riscv64). If no match is found, the first manifest in the list is used.

## License

MIT. See [LICENSE](LICENSE).
