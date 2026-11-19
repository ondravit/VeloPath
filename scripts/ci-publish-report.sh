#!/bin/bash
# Pushes build logs, errors and screenshots of the latest run to the `ci-reports` branch,
# so they can be inspected without GitHub authentication.
set -x
mkdir -p ci-out
{
  echo "# CI run ${GITHUB_RUN_NUMBER} – ${GITHUB_SHA::7} (${GITHUB_REF_NAME})"
  echo
  echo "| step | outcome |"
  echo "|---|---|"
  echo "| core tests | ${CORE} |"
  echo "| simulator build | ${BUILD} |"
  echo "| screenshots | ${SHOTS} |"
  echo "| unsigned IPA | ${IPA} |"
  echo
  echo '## Compiler errors'
  echo '```'
  grep -E "error:" ci-out/build.log ci-out/build-device.log 2>/dev/null | sort -u | head -150
  echo '```'
  echo '## Core test summary'
  echo '```'
  grep -E "error:|failed|passed|Executed|Test Suite|XCTAssert" ci-out/core-tests.log 2>/dev/null | tail -60
  echo '```'
} > ci-out/summary.md
grep -E "warning:" ci-out/build.log 2>/dev/null | grep -v "/build/SourcePackages/" | sort -u > ci-out/warnings.txt || true
tail -c 400000 ci-out/build.log > ci-out/build-tail.log 2>/dev/null || true
rm -f ci-out/build.log ci-out/build-device.log

REPO_URL="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
rm -rf ../reports
if git ls-remote --exit-code --heads "$REPO_URL" ci-reports >/dev/null 2>&1; then
  git clone --depth 1 --branch ci-reports "$REPO_URL" ../reports
else
  mkdir ../reports && cd ../reports && git init -b ci-reports && git remote add origin "$REPO_URL" && cd -
fi
rm -rf ../reports/latest
mkdir -p ../reports/latest
cp -R ci-out/. ../reports/latest/
echo "- run ${GITHUB_RUN_NUMBER} ${GITHUB_SHA::7} core=${CORE} build=${BUILD} shots=${SHOTS} ipa=${IPA} $(date -u +%FT%TZ)" >> ../reports/history.md
cd ../reports
git config user.name "velopath-ci"
git config user.email "ci@users.noreply.github.com"
git add -A
git commit -qm "CI report ${GITHUB_RUN_NUMBER} (${GITHUB_SHA::7})"
git push -q origin ci-reports
