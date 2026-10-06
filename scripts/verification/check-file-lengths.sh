#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

failures=0
warnings=0
checked=0
declare -A directory_counts=()

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
  directory_counts["$(dirname "$relative")"]=$(( ${directory_counts["$(dirname "$relative")"]:-0} + 1 ))

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

for directory in "${!directory_counts[@]}"; do
  count="${directory_counts[$directory]}"
  if (( count > 10 )); then
    printf 'ERROR %s contains %d direct handwritten code files (maximum 10)\n' "$directory" "$count"
    failures=$((failures + 1))
  fi
  if [[ "/$directory/" =~ /(part|module|chunk|section)-[0-9]+/ ]]; then
    printf 'ERROR %s uses a mechanical directory name\n' "$directory"
    failures=$((failures + 1))
  fi
done

while IFS= read -r -d '' file; do
  basename="$(basename "$file")"
  if [[ "$basename" =~ (Treeseed|TreeSeed|KnowledgeCoop) ]]; then
    printf 'ERROR %s uses a redundant product-qualified executable filename\n' "${file#./}"
    failures=$((failures + 1))
  fi
done < <(
  find . -type f \
    \( -name '*.rs' -o -name '*.ex' -o -name '*.exs' -o -name '*.ts' -o -name '*.tsx' \
       -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' -o -name '*.sh' \) \
    -not -path '*/node_modules/*' -not -path '*/deps/*' -not -path '*/_build/*' \
    -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/vendor/*' \
    -print0
)

for script in scripts/profiling/profile-compose.sh scripts/profiling/profile-treedx.sh; do
  if ! grep -Fq '$(dirname "${BASH_SOURCE[0]}")/../..' "$script"; then
    printf 'ERROR %s must resolve the repository root from its functional subdirectory\n' "$script"
    failures=$((failures + 1))
  fi
done

printf 'Checked %d handwritten code files; %d warning(s); %d error(s).\n' \
  "$checked" "$warnings" "$failures"

if (( failures > 0 )); then
  exit 1
fi
