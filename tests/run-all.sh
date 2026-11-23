#!/usr/bin/env bash
# Runs every kit test. Exit 0 only if all suites pass.
set -u
cd "$(dirname "$0")/.." || exit 1
rc=0
for t in tests/scan-secrets-test.sh tests/pre-push-test.sh tests/new-dailies-test.sh tests/session-start-test.sh tests/session-end-test.sh tests/summarize-test.sh tests/nightly-test.sh tests/compiler-doc-test.sh tests/skills-test.sh tests/template-test.sh tests/install-test.sh tests/update-test.sh tests/doctor-test.sh tests/runner-test.sh tests/workflows-test.sh tests/install-ps1-test.sh tests/docs-test.sh; do
  printf '%-32s ' "$t"
  if out="$(bash "$t" 2>&1)"; then echo "passed"; else echo "FAILED"; printf '%s\n' "$out" | grep FAIL; rc=1; fi
done
for py in tests/test_candidates.py tests/test_queue.py tests/test_manifest.py tests/test_update.py tests/test_merge_gate.py; do printf '%-32s ' "$py"
if out="$(python3 -m unittest "$py" 2>&1)"; then echo "passed"; else echo "FAILED"; printf '%s\n' "$out" | tail -20; rc=1; fi; done
rm -rf tests/__pycache__ compiler/__pycache__ kit/__pycache__
exit "$rc"
