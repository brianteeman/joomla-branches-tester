#!/bin/bash
#
# clean.sh - delete all jbt_* Docker containers and the network joomla-branches-tester_default.
#
# Distributed under the GNU General Public License version 2 or later, Copyright (c) 2024 Heiko Lübbe
# https://github.com/muhme/joomla-branches-tester

source scripts/helper.sh

versions=$(getVersions)
IFS=' ' allVersions=($(sort <<<"${versions}")); unset IFS # map to array

# Delete all docker containters (PHP version does not play a role for deletion)
createDockerComposeFile "${allVersions[*]}" "php8.2"

log 'Stopping and removing JBT Docker containers, associated Docker networks and volumes.'
docker compose down -v

# Clean up branch directories if existing
for version in "${allVersions[@]}"; do
  if [ -d "branch_${version}" ]; then
    log "Removing directory 'branch_${version}'."
    # sudo is needed on Windows WSL Ubuntu
    rm -rf "branch_${version}" >/dev/null 2>&1 || sudo rm -rf "branch_${version}"
  fi
done
