#!/bin/bash
# Tests the release scripts without touching the login keychain or a real
# remote: signatures here are ad-hoc only, and pushes go to a local bare
# repository.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /tmp/o2i-release-checks.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
FAILURES=0

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# expect <exit code> <stderr substring or empty> -- <command...>
expect() {
    local want_code="$1" want_err="$2"
    shift 3
    local err code
    err="$("$@" 2>&1 >/dev/null)"
    code=$?
    if [ "$code" -ne "$want_code" ]; then
        fail "$* exited $code, want $want_code ($err)"
    elif [ -n "$want_err" ] && [[ "$err" != *"$want_err"* ]]; then
        fail "$* stderr '$err' lacks '$want_err'"
    fi
}

cat > "$WORK/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
</dict>
</plist>
PLIST

TAG="$ROOT/scripts/check-tag-version.sh"
expect 0 "" -- "$TAG" v0.1.0 "$WORK/Info.plist"
expect 1 "error: tag v0.2.0 does not match CFBundleShortVersionString 0.1.0" -- "$TAG" v0.2.0 "$WORK/Info.plist"
expect 1 "error: tag 0.1.0 does not match CFBundleShortVersionString 0.1.0" -- "$TAG" 0.1.0 "$WORK/Info.plist"

APP="$WORK/Fake.app"
mkdir -p "$APP/Contents/MacOS"
cp /usr/bin/true "$APP/Contents/MacOS/Fake"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.rewse.Outlook2iCloudCal</string>
    <key>CFBundleExecutable</key>
    <string>Fake</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" 2>/dev/null || fail "ad-hoc signing the fixture failed"

SIG="$ROOT/scripts/check-signature.sh"
expect 1 "designated requirement" -- "$SIG" "$APP"
expect 1 "not found" -- "$SIG" "$WORK/Missing.app"

# A failed import must still tell the cleanup step which keychain to delete.
# `security` and `sudo` are stubs here, so no real keychain is touched.
STUBS="$WORK/stubs"
mkdir -p "$STUBS" "$WORK/runner_temp"
# shellcheck disable=SC2016 # the stubs' $1 and $@ must expand when they run
printf '#!/bin/bash\n[ "$1" = add-trusted-cert ] && exit 1\nexit 0\n' > "$STUBS/security"
# shellcheck disable=SC2016 # same as above
printf '#!/bin/bash\nexec "$@"\n' > "$STUBS/sudo"
chmod +x "$STUBS/security" "$STUBS/sudo"
: > "$WORK/github_env"
if PATH="$STUBS:$PATH" CI=true RUNNER_TEMP="$WORK/runner_temp" GITHUB_ENV="$WORK/github_env" \
    P12_PASSWORD=x "$ROOT/scripts/ci-import-signing-identity.sh" /dev/null >/dev/null 2>&1; then
    fail "ci-import-signing-identity.sh succeeded although trusting the certificate failed"
fi
grep -qx "SIGNING_KEYCHAIN=$WORK/runner_temp/signing.keychain-db" "$WORK/github_env" \
    || fail "a failed import did not export SIGNING_KEYCHAIN for cleanup"

# bump-version.sh runs in a scratch clone whose origin is a local bare
# repository, so no real remote is touched.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git init --quiet --bare --initial-branch=main "$WORK/origin.git"
REPO="$WORK/repo"
git init --quiet --initial-branch=main "$REPO"
mkdir -p "$REPO/scripts" "$REPO/Resources"
cp "$ROOT/scripts/bump-version.sh" "$ROOT/scripts/check-tag-version.sh" "$REPO/scripts/"
cp "$WORK/Info.plist" "$REPO/Resources/Info.plist"
git -C "$REPO" add .
git -C "$REPO" commit --quiet -m "chore: initial"
git -C "$REPO" remote add origin "$WORK/origin.git"
git -C "$REPO" push --quiet origin main
BUMP="$REPO/scripts/bump-version.sh"

expect 2 "usage" -- "$BUMP" huge
expect 2 "usage" -- "$BUMP" patch --force

expect 0 "" -- "$BUMP" minor
"$REPO/scripts/check-tag-version.sh" v0.2.0 "$REPO/Resources/Info.plist" \
    || fail "bump-version.sh minor did not set 0.2.0"
[ "$(git -C "$REPO" log -1 --format=%s)" = "chore: bump version to 0.2.0" ] \
    || fail "bump-version.sh minor did not commit the bump"
[ "$(git -C "$REPO" rev-parse "v0.2.0^{commit}")" = "$(git -C "$REPO" rev-parse HEAD)" ] \
    || fail "bump-version.sh minor did not tag HEAD as v0.2.0"
[ -z "$(git -C "$REPO" status --porcelain)" ] \
    || fail "bump-version.sh minor left the working tree dirty"

# The unpushed bump leaves main ahead of origin.
expect 1 "not in sync" -- "$BUMP" patch
git -C "$REPO" push --quiet --atomic origin main refs/tags/v0.2.0

expect 0 "" -- "$BUMP" major --push
[ "$(git -C "$WORK/origin.git" rev-parse "v1.0.0^{commit}")" = "$(git -C "$REPO" rev-parse HEAD)" ] \
    || fail "bump-version.sh major --push did not push v1.0.0"
[ "$(git -C "$WORK/origin.git" rev-parse main)" = "$(git -C "$REPO" rev-parse HEAD)" ] \
    || fail "bump-version.sh major --push did not push main"
grep -q '<string>1.0.0</string>' "$REPO/Resources/Info.plist" \
    || fail "bump-version.sh major did not set 1.0.0"

git -C "$REPO" tag v1.0.1
expect 1 "tag v1.0.1 already exists locally" -- "$BUMP" patch
git -C "$REPO" tag -d v1.0.1 >/dev/null

: > "$REPO/untracked"
expect 1 "uncommitted or untracked" -- "$BUMP" patch
rm "$REPO/untracked"

git -C "$REPO" switch --quiet -c feature
expect 1 "releases must be made from main" -- "$BUMP" patch
git -C "$REPO" switch --quiet main

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES failure(s)" >&2
    exit 1
fi
echo "PASS"
