set -e
cd "$1"
git add -A team
git diff --cached --quiet && exit 0
G="git -c user.name=Seneca -c user.email=seneca@users.noreply.github.com"
$G commit -q -m "Mitarbeiter $2 $3"
x=$(git rev-parse HEAD)
w=$(mktemp -d)
git worktree add -q --detach "$w" HEAD
trap 'git worktree remove --force "$w"' EXIT
for i in 1 2 3; do
  git fetch -q origin zusammen && git -C "$w" reset -q --hard origin/zusammen && $G -C "$w" cherry-pick "$x" >/dev/null && git -C "$w" push -q origin HEAD:zusammen && exit 0
done
exit 1
