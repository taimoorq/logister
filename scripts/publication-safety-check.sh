#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

scanner_path="scripts/publication-safety-check.sh"
sensitive_pattern='-----BEGIN [A-Z ]*PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{20,}|gh[opusr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|npm_[A-Za-z0-9_-]{20,}|pypi-[A-Za-z0-9_-]{20,}|/Users/|/home/[^/[:space:]]+/'

if git grep --untracked --exclude-standard -n -I -E -e "$sensitive_pattern" -- . \
  ":(exclude)$scanner_path" \
  ":(exclude)app/services/instance_configuration/registry.rb" \
  ":(exclude)cloudflare-docs/github-app/index.html"; then
  echo "Tracked files contain credential material or a machine-local path." >&2
  exit 1
fi

unsafe_files="$(git ls-files | grep -E '(^|/)(\.env|[^/]+\.(key|pem|p12|pfx))$|(^|/)tmp/release-' || true)"
if [ -n "$unsafe_files" ]; then
  echo "Tracked publication-unsafe files:" >&2
  printf '%s\n' "$unsafe_files" >&2
  exit 1
fi

echo "Tracked files are public-safe."
