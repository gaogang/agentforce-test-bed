#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

chmod +x .githooks/pre-commit .githooks/post-commit scripts/install-git-hooks.sh

git config core.hooksPath .githooks

echo "Git hooks installed. core.hooksPath is set to .githooks"
