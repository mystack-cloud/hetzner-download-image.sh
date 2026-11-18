#!/usr/bin/env bats
load test_helper
setup() { load_script; }

@test "bare name -> docker hub library/<name>:latest" {
  parse_image alpine
  [ "$REGISTRY" = registry-1.docker.io ]
  [ "$REPOSITORY" = library/alpine ]
  [ "$REFERENCE" = latest ]
}

@test "name with tag" {
  parse_image alpine:3.19
  [ "$REPOSITORY" = library/alpine ]
  [ "$REFERENCE" = 3.19 ]
}

@test "user/repo on docker hub" {
  parse_image myorg/app:1
  [ "$REGISTRY" = registry-1.docker.io ]
  [ "$REPOSITORY" = myorg/app ]
  [ "$REFERENCE" = 1 ]
}

@test "docker.io/library/alpine:3.19" {
  parse_image docker.io/library/alpine:3.19
  [ "$REGISTRY" = registry-1.docker.io ]
  [ "$REPOSITORY" = library/alpine ]
  [ "$REFERENCE" = 3.19 ]
}

@test "ghcr.io multi-level repo with tag" {
  parse_image ghcr.io/myorg/hetzner-images/debian-13:latest
  [ "$REGISTRY" = ghcr.io ]
  [ "$REPOSITORY" = myorg/hetzner-images/debian-13 ]
  [ "$REFERENCE" = latest ]
}

@test "registry with port" {
  parse_image localhost:5000/foo/bar:v1
  [ "$REGISTRY" = localhost:5000 ]
  [ "$REPOSITORY" = foo/bar ]
  [ "$REFERENCE" = v1 ]
}

@test "digest reference" {
  parse_image ghcr.io/o/r@sha256:abc123
  [ "$REGISTRY" = ghcr.io ]
  [ "$REPOSITORY" = o/r ]
  [ "$REFERENCE" = sha256:abc123 ]
}
