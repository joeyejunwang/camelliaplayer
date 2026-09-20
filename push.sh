# git checkout --orphan latest_branch
# git add -A
# git commit -am "commit message"
# git branch -D main
# git branch -m main
# git push -f origin main

git add -A
git commit -m "1.0.20"
git push -f origin main
git tag v1.0.20
git push origin v1.0.20


