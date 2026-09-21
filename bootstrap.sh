#!/usr/bin/env bash
# bootstrap.sh — make psql available in a sandbox with no root and no
# package install rights. Downloads the Debian/Ubuntu client packages with
# apt's download-only mode into a private cache and extracts them under
# $PREFIX (default: /workspace/.local). Idempotent; safe to re-run.
#
# Usage:  source bootstrap.sh      (adds $PREFIX/bin to PATH in this shell)
#    or:  ./bootstrap.sh && export PATH=/workspace/.local/bin:$PATH
set -euo pipefail

PREFIX="${PREFIX:-/workspace/.local}"
PGBIN="$(ls -d "$PREFIX"/usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)"

if [ -x "$PREFIX/bin/psql" ]; then
  echo "psql already installed at $PREFIX/bin/psql"
else
  if command -v psql >/dev/null 2>&1; then
    echo "system psql found: $(command -v psql)"; exit 0
  fi
  echo "installing psql into $PREFIX (no root)"
  APT="$PREFIX/apt"
  mkdir -p "$APT/lists/partial" "$APT/cache/archives/partial" "$PREFIX/bin"
  APT_OPTS=(-o Dir::State::Lists="$APT/lists" -o Dir::Cache="$APT/cache"
            -o Dir::State::status=/var/lib/dpkg/status -o Debug::NoLocking=1)
  apt-get "${APT_OPTS[@]}" update -qq
  apt-get "${APT_OPTS[@]}" install -y --download-only --reinstall postgresql-client -qq
  for deb in "$APT"/cache/archives/*.deb; do dpkg-deb -x "$deb" "$PREFIX"; done
  PGBIN="$(ls -d "$PREFIX"/usr/lib/postgresql/*/bin | head -1)"
  cat > "$PREFIX/bin/psql" <<EOF
#!/bin/bash
export LD_LIBRARY_PATH=$PREFIX/usr/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH:-}
exec $PGBIN/psql "\$@"
EOF
  chmod +x "$PREFIX/bin/psql"
  rm -rf "$APT/cache/archives"/*.deb
  echo "installed: $("$PREFIX/bin/psql" --version)"
fi

export PATH="$PREFIX/bin:$PATH"

# Sanity checks the agent should see.
if [ -z "${DATABASE_URL:-}" ]; then
  echo "WARNING: DATABASE_URL is not set"
else
  case "$DATABASE_URL" in
    *\'|\'*|*\"|\"*) echo "WARNING: DATABASE_URL has stray quotes; fix the secret value" ;;
  esac
  if psql "$DATABASE_URL" -tAc 'select 1' >/dev/null 2>&1; then
    echo "database connection OK"
  else
    echo "WARNING: cannot connect to the database (check Trusted Sources / egress)"
  fi
fi
