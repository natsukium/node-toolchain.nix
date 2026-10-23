#!/usr/bin/env nix
#! nix shell --inputs-from ../dev nixpkgs#bash nixpkgs#coreutils nixpkgs#curl nixpkgs#jq nixpkgs#gawk --command bash
# Regenerates versions/*.json from upstream release metadata.
# Released artifacts never change, so only versions missing from the catalog are fetched.
set -euo pipefail

out=${1:-versions}
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

packument() {
  curl -fsSL -H 'Accept: application/vnd.npm.install-v1+json' "https://registry.npmjs.org/$1"
}

# Node.js: {version: {system: sha256 hex of the .tar.xz}}, from 14.0.0 on.
[ -f "$out/nodejs.json" ] || echo '{}' >"$out/nodejs.json"
curl -fsSL https://nodejs.org/dist/index.json |
  jq -r --slurpfile known "$out/nodejs.json" '
    .[]
    | (.version | ltrimstr("v")) as $v
    | select(($v | split(".") | .[0] | tonumber) >= 14)
    | select($known[0] | has($v) | not)
    | $v' >"$tmp/missing"

echo "nodejs: fetching $(wc -l <"$tmp/missing" | tr -d ' ') new versions" >&2
mkdir -p "$tmp/shasums"
xargs -P 8 -I{} curl -fsSL -o "$tmp/shasums/{}" "https://nodejs.org/dist/v{}/SHASUMS256.txt" <"$tmp/missing"

for f in "$tmp"/shasums/*; do
  [ -e "$f" ] || continue
  v=$(basename "$f")
  awk -v v="$v" '
    $2 == "node-v" v "-darwin-arm64.tar.xz" { print "aarch64-darwin", $1 }
    $2 == "node-v" v "-linux-arm64.tar.xz" { print "aarch64-linux", $1 }
    $2 == "node-v" v "-linux-x64.tar.xz" { print "x86_64-linux", $1 }
  ' "$f" | jq -R -n --arg v "$v" '{($v): ([inputs | split(" ") | {(.[0]): .[1]}] | add // {})}'
done | jq -s -S --slurpfile known "$out/nodejs.json" '$known[0] + (add // {})' \
  >"$tmp/nodejs.json"
mv "$tmp/nodejs.json" "$out/nodejs.json"

# pnpm: {version: {integrity, bin, exe?: {system: integrity}}}. The registry lists every
# version in one document per package, so this is regenerated in full.
# Entry points moved between bin/ and lib/bin/ and across .js, .cjs and .mjs more than
# once, so they are recorded rather than derived from the version.
packument pnpm | jq '.versions | map_values({integrity: .dist.integrity, bin: (.bin // {})})' >"$tmp/pnpm"
for target in darwin-arm64:aarch64-darwin linux-arm64-musl:aarch64-linux linux-x64-musl:x86_64-linux; do
  packument "@pnpm/exe.${target%%:*}" | jq --arg s "${target##*:}" '.versions | map_values({($s): .dist.integrity})'
done | jq -s 'reduce .[] as $x ({}; . * $x)' >"$tmp/pnpm-exe"

jq -S -n --slurpfile w "$tmp/pnpm" --slurpfile e "$tmp/pnpm-exe" '
  $w[0] | with_entries(
    .key as $v
    | .value = (.value + (if $e[0] | has($v) then {exe: $e[0][$v]} else {} end))
  )' >"$out/pnpm.json"

echo "nodejs: $(jq length "$out/nodejs.json") versions, pnpm: $(jq length "$out/pnpm.json") versions" >&2
