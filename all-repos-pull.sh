find -type d -name ".git" | sort | while IFS= read -r repo;
do
 pushd "$(dirname $repo)"
 git status -s
 git fetch
 git merge -q --ff-only
 popd
done
