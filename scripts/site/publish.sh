#!/usr/bin/env bash
# Publish only the static artifact to gh-pages; source stays on its review branch.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"
node_bin="${NODE_BIN:-node}"
"$node_bin" tests/test_web_mockup.mjs
if [[ ! -f site/assets/basemap.json ]]; then
  echo 'Configure the CARTO browser basemap first: Rscript scripts/site/configure_basemap.R [environment-file]' >&2
  exit 1
fi
publish_remote="$(git remote get-url origin)"
source_commit="$(git rev-parse HEAD)"
publish_dir="$(mktemp -d "${TMPDIR:-/tmp}/opportunity-pages.XXXXXX")"
trap 'rm -rf "$publish_dir"' EXIT
remote_branch="$(git ls-remote --heads "$publish_remote" gh-pages)"
if [[ -n "$remote_branch" ]]; then
  git clone --quiet --depth 1 --branch gh-pages "$publish_remote" "$publish_dir"
else
  git init --quiet --initial-branch=gh-pages "$publish_dir"
  git -C "$publish_dir" remote add origin "$publish_remote"
fi
rsync -a --delete --exclude=.git site/ "$publish_dir/"
# A content version prevents browsers from retaining an earlier stylesheet.
"$node_bin" --input-type=module - "$publish_dir" <<'JS'
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const directory=process.argv[2];
const cssHash=createHash('sha256').update(readFileSync(directory+'/style.css')).digest('hex').slice(0,12);
const html=readFileSync(directory+'/index.html','utf8').replace('href="style.css"',`href="style.css?v=${cssHash}"`);
writeFileSync(directory+'/index.html',html);
JS
printf '{"source_commit":"%s"}\n' "$source_commit" > "$publish_dir/deployment.json"
git -C "$publish_dir" add --all
if git -C "$publish_dir" diff --cached --quiet; then
  echo 'Published artifact is already current.'
  exit 0
fi
git -C "$publish_dir" commit -m "Publish opportunity map from $source_commit"
git -C "$publish_dir" push origin gh-pages
