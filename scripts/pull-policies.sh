#!/usr/bin/env bash
# Fetches terms.md and privacy.md from a Policies repo and writes them into
# ./policies as TERMS.md / PRIVACY.md, which is what the frontend's
# POLICIES_DIR expects. Re-run any time to refresh, then
# `docker compose restart frontend` to pick up the change — it's read once
# at startup.
#
# Usage: ./scripts/pull-policies.sh [owner/repo] [ref]
#   Defaults to TrP-Labs/Policies at its "prod" branch. Point this at a fork
#   (e.g. your-org/Policies) to publish your own text instead.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

REPO="${1:-TrP-Labs/Policies}"
REF="${2:-prod}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"

mkdir -p policies

fetch_one() {
	# fetch_one <source-filename-candidates...> <dest-filename>
	local dest=${*: -1}
	local candidates=("${@:1:$#-1}")
	local name
	for name in "${candidates[@]}"; do
		if curl -fsSL "$RAW/$name" -o "policies/$dest.tmp" 2>/dev/null; then
			mv "policies/$dest.tmp" "policies/$dest"
			echo "Pulled $name -> policies/$dest"
			return 0
		fi
	done
	rm -f "policies/$dest.tmp"
	echo "warning: no ${candidates[0]} (or similarly-cased file) found at $REPO@$REF — skipping $dest" >&2
	return 1
}

status=0
fetch_one terms.md TERMS.md TERMS.md || status=1
fetch_one privacy.md PRIVACY.md PRIVACY.md || status=1

if [ "$status" -ne 0 ]; then
	echo "Some policy files were not pulled; the corresponding page(s) on the" >&2
	echo "site will 404 until they're present in ./policies." >&2
fi
exit 0
