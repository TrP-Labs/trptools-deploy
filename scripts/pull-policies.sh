#!/usr/bin/env bash
# Mirrors a Policies repository into ./policies, which is what the frontend
# serves its footer bar from. Re-run any time to refresh, then
# `docker compose restart frontend` to pick up the change — it's read once
# at startup.
#
# Every .md and .txt in the source is copied across **under its own name**,
# because that name is the link's label on the site: "Privacy Policy.md"
# becomes a page linked as "Privacy Policy", and "About.txt" becomes a link
# straight to the URL inside it. Nothing is renamed or case-corrected here;
# doing so would silently rewrite what the site says.
#
# Usage: ./scripts/pull-policies.sh [owner/repo] [ref]
#   Defaults to TrP-Labs/Policies at its default branch. Point this at a fork
#   (e.g. your-org/Policies) to publish your own text instead.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

REPO="${1:-TrP-Labs/Policies}"
REF="${2:-main}"
API="https://api.github.com/repos/$REPO/contents?ref=$REF"

mkdir -p policies

listing=$(curl -fsSL -H 'Accept: application/vnd.github+json' "$API" 2>/dev/null) || {
	echo "error: could not list $REPO@$REF." >&2
	echo "Check the repository and branch exist and are public. Unauthenticated" >&2
	echo "GitHub API calls are also rate limited to 60/hour per address." >&2
	exit 1
}

# `name` and `download_url` only; anything that is not a plain file is skipped,
# so a subdirectory in the source cannot surprise us with a path to write to.
# Read into an array the long way rather than with `mapfile`, which macOS's
# bash 3.2 does not have — this script is run on laptops as well as servers.
entries=()
while IFS= read -r line; do
	[ -n "$line" ] && entries+=("$line")
done < <(printf '%s' "$listing" | python3 -c '
import json, sys
for item in json.load(sys.stdin):
    if item.get("type") != "file":
        continue
    name = item["name"]
    if not name.lower().endswith((".md", ".txt")):
        continue
    print(name + "\t" + item["download_url"])
')

if [ "${#entries[@]}" -eq 0 ]; then
	echo "warning: $REPO@$REF holds no .md or .txt files, so the site's footer" >&2
	echo "bar will be empty." >&2
	exit 0
fi

pulled=()
for entry in "${entries[@]}"; do
	name=${entry%%$'\t'*}
	url=${entry#*$'\t'}

	if curl -fsSL "$url" -o "policies/$name.tmp"; then
		mv "policies/$name.tmp" "policies/$name"
		pulled+=("$name")
		echo "Pulled $name"
	else
		rm -f "policies/$name.tmp"
		echo "warning: could not download $name" >&2
	fi
done

# Files left behind by a previous pull are the trap here: the source renaming
# "TERMS.md" to "Terms Of Service.md" leaves both sitting in ./policies, and
# the site dutifully shows two links. They are reported rather than deleted,
# because an operator may have dropped their own files in here by hand.
shopt -s nullglob
for existing in policies/*.md policies/*.txt; do
	name=$(basename "$existing")
	for kept in "${pulled[@]}"; do
		[ "$name" = "$kept" ] && continue 2
	done
	echo "note: policies/$name is not in $REPO@$REF — delete it unless it is yours," >&2
	echo "      or the site will keep offering it." >&2
done
