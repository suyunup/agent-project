#!/bin/sh
# Run a command with ClipWeave's toolchain without changing the global shell.
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ClipWeave development currently requires macOS." >&2
  exit 1
fi

if [ -d /opt/homebrew/opt/node@24 ]; then
  clipweave_brew_prefix=/opt/homebrew
elif [ -d /usr/local/opt/node@24 ]; then
  clipweave_brew_prefix=/usr/local
else
  echo "Node 24 is missing. Install it with: brew install node@24" >&2
  exit 1
fi

export PATH="$clipweave_brew_prefix/opt/node@24/bin:$clipweave_brew_prefix/opt/rustup/bin:$HOME/.cargo/bin:$clipweave_brew_prefix/bin:$PATH"

# Keep an explicitly selected developer directory; otherwise use the newer CLT.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

if [ "$#" -eq 0 ]; then
  echo "Usage: sh scripts/with-dev-env.sh <command> [arguments...]" >&2
  exit 2
fi

exec "$@"
