find -type d -name ".git" | sort | while IFS= read -r repo;
do
 if [ -e "$(dirname $repo)/.dormant"      ]; then continue; fi
 if [ -e "$(dirname $repo)/.diarydormant" ]; then continue; fi
 pushd   "$(dirname $repo)" > /dev/null
 echo     $(dirname $repo) 
 git status -s


 popd > /dev/null
done
