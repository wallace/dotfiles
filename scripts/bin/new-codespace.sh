#!/bin/bash
# usage
# ./new-codespace.sh master to grab the latest dotcom master <-- this is fast
# ./new-codespace.sh <branch-name> to grab another branch    <-- this is not so fast
set -x

results=$(gh cs create -b $1 -r github/github -m xLargePremiumLinux)
gh cs code -c $results
