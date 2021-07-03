find -type d -name ".git" | sort | while IFS= read -r repo; do pushd "$(dirname $repo)"; git pull -q --ff-only; popd; done
