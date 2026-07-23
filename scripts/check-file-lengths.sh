#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

failures=0
warnings=0
checked=0

while IFS= read -r -d '' file; do
  relative="${file#./}"

  case "$relative" in
    */node_modules/*|*/deps/*|*/_build/*|*/target/*|*/dist/*|*/build/*|*/vendor/*|*/coverage/*)
      continue
      ;;
    */generated/*|*/migrations/*|*/snapshots/*|*.lock|*.min.js)
      continue
      ;;
  esac

  lines="$(wc -l < "$file")"
  checked=$((checked + 1))

  if (( lines > 500 )); then
    printf 'ERROR %s has %d lines (maximum 500)\n' "$relative" "$lines"
    failures=$((failures + 1))
  elif (( lines > 350 )); then
    printf 'WARN  %s has %d lines (target 250-350)\n' "$relative" "$lines"
    warnings=$((warnings + 1))
  fi
done < <(
  find . -type f \
    \( -name '*.rs' -o -name '*.ex' -o -name '*.exs' -o -name '*.ts' -o -name '*.tsx' \
       -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' -o -name '*.sh' \) \
    -print0
)

printf 'Checked %d handwritten code files; %d warning(s); %d error(s).\n' \
  "$checked" "$warnings" "$failures"

if (( failures > 0 )); then
  exit 1
fi
