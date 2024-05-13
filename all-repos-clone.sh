cat ~/managed-scripts/borans_repos.txt | while read -r repo; do git clone $repo; done
