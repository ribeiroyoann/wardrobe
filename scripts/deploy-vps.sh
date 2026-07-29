#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=/srv/personal-apps/wardrobe
WORKSPACE=/home/yoann-dev/src/wardrobe
LOCK_FILE=/run/lock/wardrobe.lock

if [[ ${1:-} == rollback ]]; then
  mapfile -t releases < <(sudo find "$APP_ROOT/releases" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
  [[ ${#releases[@]} -ge 2 ]] || { echo "No previous release is available." >&2; exit 1; }
  target=${2:-${releases[1]}}
  sudo test -d "$APP_ROOT/releases/$target" || { echo "Unknown release: $target" >&2; exit 1; }
  image="wardrobe:$target"
  sudo docker image inspect "$image" >/dev/null
  current=$(basename "$(readlink -f "$APP_ROOT/current")")
  echo "Rolling back application $current -> $target; persistent data will not be changed."
  sudo flock "$LOCK_FILE" bash -c "
    cd '$APP_ROOT/releases/$current' &&
    WARDROBE_IMAGE='wardrobe:$current' docker compose down &&
    cd '$APP_ROOT/releases/$target' &&
    WARDROBE_IMAGE='$image' docker compose up -d &&
    ln -sfn '$APP_ROOT/releases/$target' '$APP_ROOT/current'
  "
  exit 0
fi

cd "$WORKSPACE"
[[ -z $(git status --porcelain) ]] || { echo "Refusing to deploy a dirty workspace." >&2; exit 1; }
commit=$(git rev-parse HEAD)
branch=$(git symbolic-ref --short HEAD)
git merge-base --is-ancestor "$commit" "origin/$branch" ||
  { echo "Refusing to deploy commit $commit because it is not pushed to origin/$branch." >&2; exit 1; }

release=$(date -u +%Y%m%dT%H%M%SZ)
release_dir="$APP_ROOT/releases/$release"
image="wardrobe:$release"
echo "Deploying exact Git commit $commit as release $release"

sudo install -d -o personal-apps -g personal-apps "$release_dir"
git archive "$commit" | sudo -u personal-apps tar -x -C "$release_dir"
sudo docker build --pull -t "$image" "$release_dir"

previous=
if sudo test -L "$APP_ROOT/current"; then
  previous=$(basename "$(sudo readlink -f "$APP_ROOT/current")")
fi

sudo flock "$LOCK_FILE" bash -c "
  set -e
  if [ -n '$previous' ]; then
    cd '$APP_ROOT/releases/$previous'
    WARDROBE_IMAGE='wardrobe:$previous' docker compose down
  fi
  cd '$release_dir'
  WARDROBE_IMAGE='$image' docker compose up -d
"

healthy=
for _ in {1..24}; do
  status=$(sudo docker inspect --format '{{.State.Health.Status}}' wardrobe 2>/dev/null || true)
  if [[ $status == healthy ]]; then healthy=1; break; fi
  sleep 5
done

if [[ -z $healthy ]] || ! curl --fail --silent http://127.0.0.1:3210/api/import/wardrobe |
  jq -e 'type == "array"' >/dev/null; then
  echo "Release $release failed validation; application rollback only." >&2
  sudo bash -c "cd '$release_dir' && WARDROBE_IMAGE='$image' docker compose down"
  if [[ -n $previous ]]; then
    sudo bash -c "cd '$APP_ROOT/releases/$previous' && WARDROBE_IMAGE='wardrobe:$previous' docker compose up -d"
  fi
  exit 1
fi

sudo ln -sfn "$release_dir" "$APP_ROOT/current"
echo "Release $release is healthy and current at commit $commit."
