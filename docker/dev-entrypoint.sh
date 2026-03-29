#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${PG_SOURCE_DIR:-/src}"
WORKSPACE_DIR="${PG_WORKSPACE_DIR:-/workspace}"
BUILD_DIR="${PG_BUILD_DIR:-$WORKSPACE_DIR/build}"
DATA_DIR="${PGDATA:-$WORKSPACE_DIR/data}"
LOG_DIR="${PG_LOG_DIR:-$WORKSPACE_DIR/log}"
CCACHE_DIR="${CCACHE_DIR:-$WORKSPACE_DIR/.ccache}"
BUILD_JOBS="${PG_BUILD_JOBS:-$(nproc)}"
TEST_JOBS="${PG_TEST_JOBS:-$(nproc)}"
PGPORT="${PGPORT:-55432}"
PG_CI_BASE_CONF="$SOURCE_DIR/src/tools/ci/pg_ci_base.conf"
TMP_INSTALL_ROOT="$BUILD_DIR/tmp_install/usr/local/pgsql"
TMP_INSTALL_BIN="$TMP_INSTALL_ROOT/bin"
TMP_INSTALL_LIB_BASE="$TMP_INSTALL_ROOT/lib"

readonly SOURCE_DIR
readonly WORKSPACE_DIR
readonly BUILD_DIR
readonly DATA_DIR
readonly LOG_DIR
readonly CCACHE_DIR
readonly BUILD_JOBS
readonly TEST_JOBS
readonly PGPORT
readonly PG_CI_BASE_CONF
readonly TMP_INSTALL_ROOT
readonly TMP_INSTALL_BIN
readonly TMP_INSTALL_LIB_BASE

MESON_BASE_ARGS=(
  -Dcassert=true
  -Ddocs=enabled
  -Ddocs_pdf=disabled
  -Dinjection_points=true
  --buildtype=debug
  -Dtap_tests=enabled
  -Dnls=enabled
  -Dicu=enabled
  -Dldap=enabled
  -Dlibcurl=enabled
  -Dlibnuma=enabled
  -Dliburing=enabled
  -Dlibxml=enabled
  -Dlibxslt=enabled
  -Dlz4=enabled
  -Dllvm=disabled
  -Dplperl=enabled
  -Dplpython=enabled
  -Dpltcl=enabled
  -Dreadline=enabled
  -Dssl=openssl
  -Duuid=e2fs
  -Dzlib=enabled
  -Dzstd=enabled
)
SUPPORTED_MESON_OPTIONS=()
FILTERED_MESON_ARGS=()

ensure_dirs() {
  mkdir -p "$WORKSPACE_DIR" "$LOG_DIR" "$CCACHE_DIR"
}

find_meson_options_file() {
  local path

  for path in "$SOURCE_DIR/meson.options" "$SOURCE_DIR/meson_options.txt"; do
    if [ -f "$path" ]; then
      printf '%s' "$path"
      return 0
    fi
  done

  return 1
}

load_supported_meson_options() {
  local options_file

  if [ "${#SUPPORTED_MESON_OPTIONS[@]}" -gt 0 ]; then
    return
  fi

  options_file="$(find_meson_options_file)" || {
    echo "could not find meson options file in $SOURCE_DIR" >&2
    exit 1
  }

  while IFS= read -r option_name; do
    SUPPORTED_MESON_OPTIONS+=("$option_name")
  done < <(sed -n "s/^[[:space:]]*option('\\([^']*\\)'.*/\\1/p" "$options_file")
}

filter_meson_base_args() {
  local arg
  local option_name
  local supported_option
  local is_supported

  load_supported_meson_options
  FILTERED_MESON_ARGS=()

  for arg in "${MESON_BASE_ARGS[@]}"; do
    case "$arg" in
      -D*=*)
        option_name="${arg#-D}"
        option_name="${option_name%%=*}"
        is_supported=0

        for supported_option in "${SUPPORTED_MESON_OPTIONS[@]}"; do
          if [ "$supported_option" = "$option_name" ]; then
            is_supported=1
            break
          fi
        done

        if [ "$is_supported" -eq 1 ]; then
          FILTERED_MESON_ARGS+=("$arg")
        fi
        ;;
      *)
        FILTERED_MESON_ARGS+=("$arg")
        ;;
    esac
  done
}

has_complete_build_dir() {
  [ -f "$BUILD_DIR/build.ninja" ] && [ -d "$BUILD_DIR/meson-private" ]
}

ensure_dev_pg_hba() {
  local hba_file="$DATA_DIR/pg_hba.conf"
  local marker="# pgdev docker access"

  if [ ! -f "$hba_file" ]; then
    return
  fi

  if grep -Fq "$marker" "$hba_file"; then
    return
  fi

  cat >>"$hba_file" <<EOF

$marker
host    all             all             0.0.0.0/0               trust
host    all             all             ::0/0                   trust
host    replication     all             0.0.0.0/0               trust
host    replication     all             ::0/0                   trust
EOF
}

ensure_tmp_install_env() {
  if [ ! -x "$TMP_INSTALL_BIN/postgres" ]; then
    echo "temporary install is missing; run build or runningcheck first" >&2
    exit 1
  fi

  export PATH="$TMP_INSTALL_BIN:$PATH"
  local lib_paths=()

  if [ -d "$TMP_INSTALL_LIB_BASE" ]; then
    lib_paths+=("$TMP_INSTALL_LIB_BASE")
    while IFS= read -r dir; do
      lib_paths+=("$dir")
    done < <(find "$TMP_INSTALL_LIB_BASE" -mindepth 1 -maxdepth 1 -type d | sort)
  fi

  local joined_lib_paths=""
  if [ "${#lib_paths[@]}" -gt 0 ]; then
    joined_lib_paths="$(printf '%s:' "${lib_paths[@]}")"
    joined_lib_paths="${joined_lib_paths%:}"
  fi

  export LD_LIBRARY_PATH="${joined_lib_paths}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export PGPORT
}

configure_build() {
  ensure_dirs
  filter_meson_base_args

  if [ -d "$BUILD_DIR/meson-private" ] && [ ! -f "$BUILD_DIR/build.ninja" ]; then
    rm -rf "$BUILD_DIR"
  fi

  local reconfigure=()
  if has_complete_build_dir; then
    reconfigure=(--reconfigure)
  fi

  env CC="ccache gcc" CXX="ccache g++" CCACHE_DIR="$CCACHE_DIR" \
    meson setup \
    "${reconfigure[@]}" \
    "${FILTERED_MESON_ARGS[@]}" \
    "$@" \
    "$BUILD_DIR" \
    "$SOURCE_DIR"
}

ensure_configured() {
  if ! has_complete_build_dir; then
    configure_build
  fi
}

build_tree() {
  ensure_configured
  env CCACHE_DIR="$CCACHE_DIR" \
    ninja -C "$BUILD_DIR" -j"$BUILD_JOBS" all testprep "$@"
}

build_docs() {
  configure_build

  local doc_targets=("$@")
  if [ "${#doc_targets[@]}" -eq 0 ]; then
    doc_targets=(docs)
  fi

  env CCACHE_DIR="$CCACHE_DIR" \
    meson compile -C "$BUILD_DIR" "${doc_targets[@]}"

  printf 'built docs under %s/doc/src/sgml\n' "$BUILD_DIR"
}

run_tests() {
  build_tree
  env CCACHE_DIR="$CCACHE_DIR" \
    meson test --print-errorlogs --no-rebuild -C "$BUILD_DIR" \
    --num-processes "$TEST_JOBS" "$@"
}

prepare_tmp_install() {
  build_tree
  env CCACHE_DIR="$CCACHE_DIR" \
    meson test --quiet --no-rebuild -C "$BUILD_DIR" --suite setup
}

initialize_data_dir() {
  ensure_tmp_install_env
  rm -rf "$DATA_DIR"
  initdb -D "$DATA_DIR" --auth=trust --no-instructions --no-sync
  ensure_dev_pg_hba
}

start_server_background() {
  ensure_tmp_install_env
  mkdir -p "$LOG_DIR"
  pg_ctl -D "$DATA_DIR" \
    -l "$LOG_DIR/postgres.log" \
    -o "-c fsync=off -c listen_addresses='*' -c port=$PGPORT" \
    start
}

stop_server_background() {
  ensure_tmp_install_env
  if [ -f "$DATA_DIR/postmaster.pid" ]; then
    pg_ctl -D "$DATA_DIR" stop
  fi
}

run_runningcheck() {
  prepare_tmp_install
  initialize_data_dir
  if [ -f "$PG_CI_BASE_CONF" ]; then
    printf "include '%s'\n" "$PG_CI_BASE_CONF" >> "$DATA_DIR/postgresql.conf"
  fi

  trap stop_server_background EXIT
  start_server_background

  env CCACHE_DIR="$CCACHE_DIR" \
    meson test --print-errorlogs --no-rebuild -C "$BUILD_DIR" \
    --num-processes "$TEST_JOBS" --setup running "$@"
}

run_server() {
  prepare_tmp_install
  ensure_tmp_install_env

  if [ ! -s "$DATA_DIR/PG_VERSION" ]; then
    initdb -D "$DATA_DIR" --auth=trust --no-instructions --no-sync
  fi

  ensure_dev_pg_hba

  exec postgres -D "$DATA_DIR" \
    -c fsync=off \
    -c listen_addresses='*' \
    -c port="$PGPORT"
}

open_shell() {
  exec bash
}

show_help() {
  cat <<'EOF'
Usage: pg-dev-entrypoint <command> [args...]

Commands:
  configure     Create or reconfigure the Meson build directory
  build         Compile PostgreSQL and test dependencies
  docs          Build PostgreSQL HTML/man docs
  test          Run the default Meson test suite
  runningcheck  Run tests against a manually started server
  server        Initialize PGDATA if needed and run postgres in foreground
  shell         Open an interactive shell
EOF
}

case "${1:-shell}" in
  configure)
    shift
    configure_build "$@"
    ;;
  build)
    shift
    build_tree "$@"
    ;;
  docs)
    shift
    build_docs "$@"
    ;;
  test)
    shift
    run_tests "$@"
    ;;
  runningcheck)
    shift
    run_runningcheck "$@"
    ;;
  server)
    shift
    run_server "$@"
    ;;
  shell)
    shift
    open_shell "$@"
    ;;
  help|-h|--help)
    show_help
    ;;
  *)
    exec "$@"
    ;;
esac
