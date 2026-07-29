#!/usr/bin/env bash
set -euo pipefail

direction=${1:-}
apply=${2:-}
[[ $direction == pull || $direction == push ]] ||
  { echo "Usage: $0 pull|push [--apply]" >&2; exit 2; }
[[ -z $apply || $apply == --apply ]] ||
  { echo "Only --apply is accepted as the second argument." >&2; exit 2; }

LOCAL_DATA=${WARDROBE_LOCAL_DATA:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data"}
REMOTE=${WARDROBE_VPS_SSH:-vps}
REMOTE_ROOT=/srv/personal-apps/wardrobe
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

validate() {
  local root=$1
  local allow_excluded_local=${2:-}
  jq -e 'type == "array" and length == 18' "$root/library.json" >/dev/null
  [[ $(find "$root/imported" -maxdepth 1 -type f -name '*-garment.png' | wc -l) -eq 18 ]]
  [[ $(find "$root/imported" -maxdepth 1 -type f -name '*-modeled.png' | wc -l) -eq 18 ]]
  [[ -f $root/fit-model-reference.png ]]
  if [[ $allow_excluded_local != allow-excluded-local ]]; then
    [[ ! -e $root/model-reference.png && ! -e $root/jobs && ! -e $root/.env ]]
  fi
  while IFS= read -r url; do
    [[ -f "$root/imported/${url##*/}" ]] || { echo "Missing asset for $url" >&2; return 1; }
  done < <(jq -r '.[] | .image, .modeledImage' "$root/library.json")
}

manifest() {
  local root=$1
  (
    cd "$root"
    printf 'entries\t%s\n' "$(jq length library.json)"
    printf 'files\t%s\n' "$(find imported -type f | wc -l)"
    printf 'bytes\t%s\n' "$(du -sb library.json imported fit-model-reference.png | awk '{s+=$1} END {print s}')"
    find library.json imported fit-model-reference.png -type f -print0 |
      sort -z | xargs -0 sha256sum
  )
}

if [[ $direction == pull ]]; then
  [[ -d $LOCAL_DATA ]] || { echo "Missing local destination: $LOCAL_DATA" >&2; exit 1; }
  ssh "$REMOTE" "sudo test -f '$REMOTE_ROOT/data/library.json' && sudo test -d '$REMOTE_ROOT/data/imported' && sudo test -f '$REMOTE_ROOT/data/fit-model-reference.png'"
  rsync -a --delete --dry-run --itemize-changes \
    --include='/library.json' --include='/fit-model-reference.png' --include='/imported/***' --exclude='*' \
    "$REMOTE:$REMOTE_ROOT/data/" "$LOCAL_DATA/"
  echo "Direction: VPS -> Arch"
  ssh "$REMOTE" "sudo du -sh '$REMOTE_ROOT/data'"
  du -sh "$LOCAL_DATA"
  [[ $apply == --apply ]] || { echo "Dry-run only. Re-run with --apply to mutate."; exit 0; }
  rsync -a --rsync-path='sudo rsync' \
    --include='/library.json' --include='/fit-model-reference.png' --include='/imported/***' --exclude='*' \
    "$REMOTE:$REMOTE_ROOT/data/" "$stage/"
  validate "$stage"
  mkdir -p "$LOCAL_DATA-backups"
  tar -C "$LOCAL_DATA" -czf "$LOCAL_DATA-backups/$timestamp.tar.gz" library.json imported fit-model-reference.png
  install -m 0644 "$stage/library.json" "$LOCAL_DATA/library.json"
  install -m 0644 "$stage/fit-model-reference.png" "$LOCAL_DATA/fit-model-reference.png"
  rsync -a --delete "$stage/imported/" "$LOCAL_DATA/imported/"
  validate "$LOCAL_DATA" allow-excluded-local
  manifest "$LOCAL_DATA"
else
  validate "$LOCAL_DATA" allow-excluded-local
  ssh "$REMOTE" "sudo test -d '$REMOTE_ROOT/data' && sudo test -f '$REMOTE_ROOT/data/library.json'"
  rsync -a --delete --dry-run --itemize-changes \
    --include='/library.json' --include='/fit-model-reference.png' --include='/imported/***' --exclude='*' \
    "$LOCAL_DATA/" "$REMOTE:/tmp/wardrobe-sync-preview/"
  echo "Direction: Arch -> VPS"
  du -sh "$LOCAL_DATA"
  ssh "$REMOTE" "sudo du -sh '$REMOTE_ROOT/data'"
  [[ $apply == --apply ]] || { echo "Dry-run only. Re-run with --apply to mutate."; exit 0; }
  ssh "$REMOTE" "rm -rf '/tmp/wardrobe-sync-$timestamp'; install -d '/tmp/wardrobe-sync-$timestamp/imported'"
  rsync -a "$LOCAL_DATA/library.json" "$LOCAL_DATA/fit-model-reference.png" "$REMOTE:/tmp/wardrobe-sync-$timestamp/"
  rsync -a "$LOCAL_DATA/imported/" "$REMOTE:/tmp/wardrobe-sync-$timestamp/imported/"
  ssh "$REMOTE" "sudo flock '$REMOTE_ROOT/sync.lock' bash -s" <<EOF
set -euo pipefail
stage=/tmp/wardrobe-sync-$timestamp
jq -e 'type == "array" and length == 18' "\$stage/library.json" >/dev/null
test "\$(find "\$stage/imported" -type f -name '*-garment.png' | wc -l)" -eq 18
test "\$(find "\$stage/imported" -type f -name '*-modeled.png' | wc -l)" -eq 18
test -f "\$stage/fit-model-reference.png"
test ! -e "\$stage/model-reference.png"
mkdir -p '$REMOTE_ROOT/backups'
tar -C '$REMOTE_ROOT/data' -czf '$REMOTE_ROOT/backups/data-$timestamp.tar.gz' library.json imported fit-model-reference.png
ls -1t '$REMOTE_ROOT/backups'/data-*.tar.gz | tail -n +8 | xargs -r rm --
docker stop wardrobe >/dev/null
rsync -a --delete "\$stage/" '$REMOTE_ROOT/data/'
chown -R personal-apps:personal-apps '$REMOTE_ROOT/data'
rm -rf "\$stage"
docker start wardrobe >/dev/null
EOF
  for _ in {1..24}; do
    if ssh "$REMOTE" "curl --fail --silent http://127.0.0.1:3210/api/import/wardrobe | jq -e 'length == 18' >/dev/null"; then break; fi
    sleep 5
  done
  ssh "$REMOTE" "curl --fail --silent http://127.0.0.1:3210/api/import/wardrobe | jq -e 'length == 18' >/dev/null"
  local_manifest=$(manifest "$LOCAL_DATA")
  remote_manifest=$(ssh "$REMOTE" "sudo bash -c 'cd $REMOTE_ROOT/data && find library.json imported fit-model-reference.png -type f -print0 | sort -z | xargs -0 sha256sum'")
  diff -u <(printf '%s\n' "$local_manifest" | tail -n +4) <(printf '%s\n' "$remote_manifest")
fi
