#!/bin/sh
# Check the configured image/options against independent synthetic branches.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$root/flux/apps/mergerfs/deployment.yaml"
image=$(awk '$1 == "image:" {print $2; exit}' "$manifest")
options=$(awk '$1 == "exec" && $2 == "mergerfs" {print $5}' "$manifest")
test -n "$image"
test -n "$options"
docker run --rm -i --platform linux/amd64 --privileged --network none \
  -e MERGERFS_OPTIONS="$options" --entrypoint /bin/sh "$image" -s <<'SH'
set -eu
mkdir -p /tmp/first/library /tmp/second/library /tmp/pool
trap 'umount /tmp/pool 2>/dev/null || true' EXIT
touch -t 202001010000 /tmp/first/library /tmp/second/library
mergerfs -f -o "$MERGERFS_OPTIONS" /tmp/first:/tmp/second /tmp/pool &
i=0
until grep -q ' /tmp/pool .*fuse' /proc/mounts; do
  i=$((i+1)); test "$i" -lt 50; sleep 0.1
done
mkdir /tmp/second/library/new-series
test -d /tmp/pool/library/new-series
expected=$(stat -c %Y /tmp/second/library)
actual=$(stat -c %Y /tmp/pool/library)
if test "$actual" -ne "$expected"; then
  printf 'FAIL: visible child, stale parent mtime: actual=%s expected=%s\n' "$actual" "$expected"
  exit 1
fi
printf 'PASS: new child and updated parent mtime are visible through MergerFS\n'
SH
