#!/bin/sh
# Run every git operation the backend uses, to prove the trimmed install still works.
set -eu

HOME="$(mktemp -d)"
export HOME
cd "$HOME"

git init -q -b main
git config user.name smoke
git config user.email smoke@localhost
echo one > tracked
git add .
git commit -q -m first
git branch other
git checkout -q --force -B work main
echo two >> tracked
git commit -q -a -m second
git checkout -q --force main
echo three > main-only
git add main-only
git commit -q -m third

echo four > untracked
git stash push -q --include-untracked -m smoke
git stash list --format=%gd | grep -q 'stash@{0}'
git stash apply -q --index 'stash@{0}'
git stash drop -q 'stash@{0}'
git clean -q -f -d
git reset -q --hard HEAD

git merge -q --no-commit --no-ff work
git status --porcelain | grep -q tracked
git merge --abort

test "$(git rev-list --count HEAD)" = 2
test "$(git cat-file -t HEAD)" = commit
test "$(git rev-parse --abbrev-ref HEAD)" = main
test "$(git show HEAD:tracked)" = one
test "$(git diff --name-only --diff-filter=A main work)" = ""
test "$(git diff --name-only main work | sort | tr '\n' ' ')" = "main-only tracked "
git merge-base main work > /dev/null
git log -1 --format=%H > /dev/null
git ls-tree -r --name-only HEAD | grep -q main-only
git branch --contains HEAD --format='%(refname:short)' | grep -q main
git branch -q -D other

# No server listens here: a connection error proves the HTTP transport loads.
remote="$(git ls-remote http://127.0.0.1:9/smoke.git 2>&1 || true)"
echo "$remote" | grep -qi 'connect' || { echo "git HTTP transport broken: $remote" >&2; exit 1; }

rm -rf "$HOME"
