#!/usr/bin/env bash
# Re-fetches the vendored upstream files this project tracks, pinned to the
# commit recorded in UPSTREAM_COMMIT (basecamp/omarchy, quattro branch).
#
# Run this deliberately to pick up a new upstream Omarchy revision — never as
# part of a normal build, so builds stay reproducible against a known commit.
# After running, review the diff: package-list or script changes upstream may
# require updating packages/generate-manifest.sh or docs/install-audit.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

commit="$(cat UPSTREAM_COMMIT)"
base_url="https://raw.githubusercontent.com/basecamp/omarchy/${commit}"

echo "Fetching basecamp/omarchy @ ${commit}"

curl -fsSL "$base_url/install/omarchy-base.packages" -o omarchy-base.packages
curl -fsSL "$base_url/install/omarchy-other.packages" -o omarchy-other.packages
curl -fsSL "$base_url/install/provisioning/setup-form.sh" -o ../patches/setup-form.sh
curl -fsSL "$base_url/install/provisioning/omarchy-provision-owner.service" -o ../patches/omarchy-provision-owner.service.upstream

echo "Done. Now:"
echo "  1. Review 'git diff' for anything that changes package or script semantics."
echo "  2. Re-run ./generate-manifest.sh and diff manifest.txt / excluded-report.txt."
echo "  3. Update docs/install-audit.md and wsl/omarchy-wsl-provision-owner if setup-form.sh's"
echo "     variable/function contract changed."
echo "  4. Update UPSTREAM_COMMIT to the new pinned commit once reviewed, and commit together."
