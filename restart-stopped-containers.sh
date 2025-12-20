#!/usr/bin/env bash
set -euo pipefail

printf "Scanning for docker-compose.yml files...\n"

compose_files=()
while IFS= read -r -d '' f; do
  compose_files+=("$f")
done < <(find . -maxdepth 2 -type f -name "docker-compose.yml" -print0)

if [ ${#compose_files[@]} -eq 0 ]; then
  echo "No docker-compose.yml files found."
  exit 0
fi

# Sort paths for stable output (preserve filenames with spaces)
oldIFS=$IFS
IFS=$'\n' compose_files=($(printf '%s\n' "${compose_files[@]}" | sort))
IFS=$oldIFS

printf '%-60s %-8s\n' "PROJECT" "STATUS"
printf '%-60s %-8s\n' "------------------------------------------------------------" "--------"

for file in "${compose_files[@]}"; do
  dir=$(dirname "$file")
  # include stopped/created containers for this compose project
  ids=$(docker compose -f "$file" ps -a -q 2>/dev/null || true)
  running=0

  if [ -n "$ids" ]; then
    for id in $ids; do
      st=$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || echo unknown)
      startedAt=$(docker inspect -f '{{.State.StartedAt}}' "$id" 2>/dev/null || echo '')

      # If container is not running but has been started before, start it
      if [ "$st" != "running" ]; then
        if [ -n "$startedAt" ] && [ "$startedAt" != "0001-01-01T00:00:00Z" ]; then
          docker start "$id" >/dev/null 2>&1 || true
          # re-evaluate state
          st=$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || echo unknown)
        fi
      fi

      if [ "$st" = "running" ]; then
        running=$((running+1))
      fi
    done
  fi

  status="Inactive"
  if [ "$running" -gt 0 ]; then
    status="Active"
  fi

  printf '%-60s %-8s\n' "$dir" "$status"
done

exit 0
