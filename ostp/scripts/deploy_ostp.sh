#!/usr/bin/env bash
set -euo pipefail

MODE="production"
TARGETS=("x86_64-unknown-linux-gnu")
ALL_PACKAGES=("ostp-core" "ostp-client" "ostp-server" "ostp-obfuscator")
SELECTED_PACKAGES=()
DEFAULT_PACKAGES=("ostp-client" "ostp-server")

usage() {
  cat <<EOF
Usage:
  $0                           # production build of server+client (linux x86_64)
  $0 debug                     # debug build of server+client (linux x86_64)
  $0 production client         # production build of client only
  $0 --mode debug --part core --part server
  $0 --part all                # build all workspace parts

Parts:
  all, core, client, server, obfuscator

Modes:
  production, debug
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] Missing dependency: $1"
    exit 1
  fi
}

warn_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[WARN] Optional dependency not found: $1"
    return 1
  fi
  return 0
}

check_libssl_dev() {
  if command -v dpkg >/dev/null 2>&1; then
    if ! dpkg -s libssl-dev >/dev/null 2>&1; then
      echo "[ERROR] Missing package: libssl-dev"
      echo "        Install with: sudo apt-get install -y libssl-dev"
      exit 1
    fi
  elif command -v rpm >/dev/null 2>&1; then
    if ! rpm -q openssl-devel >/dev/null 2>&1; then
      echo "[ERROR] Missing package: openssl-devel"
      echo "        Install with: sudo dnf install -y openssl-devel"
      exit 1
    fi
  else
    if ! pkg-config --exists openssl; then
      echo "[ERROR] OpenSSL development files not found via pkg-config"
      exit 1
    fi
  fi
}

part_to_package() {
  case "$1" in
    all) echo "all" ;;
    core|ostp-core) echo "ostp-core" ;;
    client|ostp-client) echo "ostp-client" ;;
    server|ostp-server) echo "ostp-server" ;;
    obfuscator|ostp-obfuscator) echo "ostp-obfuscator" ;;
    *)
      echo "[ERROR] Unknown part: $1"
      usage
      exit 1
      ;;
  esac
}

add_package() {
  local package="$1"
  local found="0"
  for current in "${SELECTED_PACKAGES[@]:-}"; do
    if [[ "$current" == "$package" ]]; then
      found="1"
      break
    fi
  done
  if [[ "$found" == "0" ]]; then
    SELECTED_PACKAGES+=("$package")
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      production|debug)
        MODE="$1"
        shift
        ;;
      core|client|server|obfuscator|all|ostp-core|ostp-client|ostp-server|ostp-obfuscator)
        local mapped
        mapped="$(part_to_package "$1")"
        if [[ "$mapped" == "all" ]]; then
          SELECTED_PACKAGES=("${ALL_PACKAGES[@]}")
        else
          add_package "$mapped"
        fi
        shift
        ;;
      --mode)
        if [[ $# -lt 2 ]]; then
          echo "[ERROR] --mode requires a value"
          usage
          exit 1
        fi
        MODE="$2"
        shift 2
        ;;
      --mode=*)
        MODE="${1#*=}"
        shift
        ;;
      --part)
        if [[ $# -lt 2 ]]; then
          echo "[ERROR] --part requires a value"
          usage
          exit 1
        fi
        local mapped
        mapped="$(part_to_package "$2")"
        if [[ "$mapped" == "all" ]]; then
          SELECTED_PACKAGES=("${ALL_PACKAGES[@]}")
        else
          add_package "$mapped"
        fi
        shift 2
        ;;
      --part=*)
        local mapped
        mapped="$(part_to_package "${1#*=}")"
        if [[ "$mapped" == "all" ]]; then
          SELECTED_PACKAGES=("${ALL_PACKAGES[@]}")
        else
          add_package "$mapped"
        fi
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "[ERROR] Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ ${#SELECTED_PACKAGES[@]} -eq 0 ]]; then
    SELECTED_PACKAGES=("${DEFAULT_PACKAGES[@]}")
  fi
}

configure_mode() {
  case "$MODE" in
    production)
      unset RUSTFLAGS || true
      export CARGO_PROFILE_RELEASE_LTO="fat"
      export CARGO_PROFILE_RELEASE_CODEGEN_UNITS="1"
      export CARGO_PROFILE_RELEASE_STRIP="symbols"
      export CARGO_PROFILE_RELEASE_PANIC="abort"
      CARGO_ARGS=(--release)
      ;;
    debug)
      unset RUSTFLAGS || true
      unset CARGO_PROFILE_RELEASE_LTO || true
      unset CARGO_PROFILE_RELEASE_CODEGEN_UNITS || true
      unset CARGO_PROFILE_RELEASE_STRIP || true
      unset CARGO_PROFILE_RELEASE_PANIC || true
      CARGO_ARGS=()
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

binary_name_for_package() {
  case "$1" in
    ostp-client) echo "ostp-client" ;;
    ostp-server) echo "ostp-server" ;;
    *) echo "" ;;
  esac
}

build_targets() {
  for target in "${TARGETS[@]}"; do
    for package in "${SELECTED_PACKAGES[@]}"; do
      echo "[INFO] Building ${package} for ${target} (${MODE})"
      cargo build "${CARGO_ARGS[@]}" --target "$target" -p "$package"

      if [[ "$MODE" == "production" ]] && command -v strip >/dev/null 2>&1; then
        local bin_name
        bin_name="$(binary_name_for_package "$package")"
        if [[ -n "$bin_name" ]]; then
          BIN_PATH="target/${target}/release/${bin_name}"
          if [[ -f "$BIN_PATH" ]]; then
            strip "$BIN_PATH" || true
          fi
        fi
      fi
    done
  done
}

set_binary_caps() {
  if ! command -v setcap >/dev/null 2>&1; then
    echo "[WARN] setcap not available, skipping capability assignment"
    return
  fi

  local profile_dir="debug"
  if [[ "$MODE" == "production" ]]; then
    profile_dir="release"
  fi

  for package in "${SELECTED_PACKAGES[@]}"; do
    # Capabilities are typically needed for tunnel interfaces in the client binary.
    if [[ "$package" != "ostp-client" ]]; then
      continue
    fi

    local bin_name
    bin_name="$(binary_name_for_package "$package")"
    if [[ -z "$bin_name" ]]; then
      continue
    fi

    for target in "${TARGETS[@]}"; do
      BIN_PATH="target/${target}/${profile_dir}/${bin_name}"
      if [[ -f "$BIN_PATH" ]]; then
        echo "[INFO] Assigning capabilities on ${BIN_PATH}"
        if [[ $EUID -ne 0 ]]; then
          sudo setcap cap_net_admin,cap_net_raw+ep "$BIN_PATH"
        else
          setcap cap_net_admin,cap_net_raw+ep "$BIN_PATH"
        fi
      fi
    done
  done
}

deploy_client_config() {
  local source_cfg="ostp-client/ostp-client.toml.example"
  if [[ ! -f "$source_cfg" ]]; then
    echo "[WARN] Client config template not found: $source_cfg"
    return
  fi

  local profile_dir="debug"
  if [[ "$MODE" == "production" ]]; then
    profile_dir="release"
  fi

  for package in "${SELECTED_PACKAGES[@]}"; do
    if [[ "$package" != "ostp-client" ]]; then
      continue
    fi

    for target in "${TARGETS[@]}"; do
      local cfg_dst="target/${target}/${profile_dir}/ostp-client.toml"
      cp "$source_cfg" "$cfg_dst"
      echo "[INFO] Deployed client config: ${cfg_dst}"
    done
  done
}

deploy_server_config() {
  local source_cfg="ostp-server/ostp-server.toml.example"
  if [[ ! -f "$source_cfg" ]]; then
    echo "[WARN] Server config template not found: $source_cfg"
    return
  fi

  local profile_dir="debug"
  if [[ "$MODE" == "production" ]]; then
    profile_dir="release"
  fi

  for package in "${SELECTED_PACKAGES[@]}"; do
    if [[ "$package" != "ostp-server" ]]; then
      continue
    fi

    for target in "${TARGETS[@]}"; do
      local cfg_dst="target/${target}/${profile_dir}/ostp-server.toml"
      cp "$source_cfg" "$cfg_dst"
      echo "[INFO] Deployed server config: ${cfg_dst}"
    done
  done
}

main() {
  parse_args "$@"

  need_cmd cargo
  need_cmd rustup
  if ! warn_cmd protoc; then
    echo "[WARN] protoc is required only for crates using protobuf code generation"
  fi
  if ! warn_cmd cmake; then
    echo "[WARN] cmake is required only for crates/dependencies that compile C/C++ sources"
  fi
  need_cmd pkg-config
  check_libssl_dev

  echo "[INFO] Build mode: ${MODE}"
  echo "[INFO] Parts: ${SELECTED_PACKAGES[*]}"

  rustup target add "${TARGETS[@]}"
  configure_mode
  build_targets
  deploy_client_config
  deploy_server_config
  set_binary_caps

  echo "[INFO] Build and deployment prep complete"
}

main "$@"
