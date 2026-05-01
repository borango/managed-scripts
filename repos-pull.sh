find -type d -name ".git" | sort | while IFS= read -r repo;
do
 if [ -e "$(dirname $repo)/.dormant"      ]; then continue; fi

 pushd   "$(dirname $repo)" > /dev/null
 echo     $(dirname $repo) 
 git status -s
 git fetch
 git merge -q --ff-only
 popd > /dev/null
done
