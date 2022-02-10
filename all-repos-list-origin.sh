find -type d -name ".git" | sort | while IFS= read -r repo; do sed -n "s/.*url\s*=\s*\(.*\.git\).*/\1/p" $repo/config ; done | sort | tee borans_repos.txt
