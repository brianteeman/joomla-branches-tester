#!/bin/bash -e
#
# patch.sh - Apply Git patches in the repositories ‘joomla-cms’, ‘joomla-cypress’ or ‘joomla-framework/database’.
#
# Distributed under the GNU General Public License version 2 or later, Copyright (c) 2024 Heiko Lübbe
# https://github.com/muhme/joomla-branches-tester

if [[ $(dirname "$0") != "scripts" || ! -f "scripts/helper.sh" ]]; then
  echo "Please run me as 'scripts/patch'. Thank you for your cooperation! :)"
  exit 1
fi

source scripts/helper.sh

function help {
  echo "
    patch – Applies Git patches in the 'joomla-cms', 'joomla-cypress' and 'joomla-framework/database'
            Joomla repositories or in 'installation/joomla-cypress' repository.
            If 'installation' option is given 'installation/joomla-cypress' is patched.
            The optional Joomla version can be one or more of: ${allInstalledInstances[*]} (default is all).
            Specify one or more patches e.g. 'joomla-cms-43968', 'joomla-cypress-33' or 'database-310'.
            The optional argument 'help' displays this page. For full details see https://bit.ly/JBT-README.
    $(random_quote)"
}

patches=()
# shellcheck disable=SC2207 # There are no spaces in version numbers
allInstalledInstances=($(getAllInstalledInstances))
instancesToPatch=()
installation=false
# Don't use "jbt-${repo_version}", use 'jbt-merged' as constant as with Git merge the repository version may change.
merge_branch="jbt-merged"

while [ $# -ge 1 ]; do
  if [[ "$1" =~ ^(help|-h|--h|-help|--help|-\?)$ ]]; then
    help
    exit 0
  elif [ "$1" = "installation" ]; then
    installation=true
    shift # Argument is eaten as patching installation/joomla-cypress.
  elif [ -d "joomla-$1" ]; then
    instancesToPatch+=("$1")
    shift # Argument is eaten as one version number.
  elif [[ "$1" =~ ^(joomla-cms|joomla-cypress|database)-[0-9]+$ ]]; then
    patches+=("$1")
    shift # Argument is eaten as one patch.
  else
    help
    error "Argument '$1' is not valid."
    exit 1
  fi
done

if [ ${#patches[@]} -eq 0 ]; then
  help
  error "Please provide at least one patch, e.g. 'joomla-cypress-33'."
  exit 1
fi

# Patching 'installation/joomla-cypress'
if [[ "$installation" == true ]]; then
  # Without instance number
  if [ ${#instancesToPatch[@]} -ne 0 ]; then
    help
    error "Patching 'installation/joomla-cypress' don't need Joomla version."
    exit 1
  fi
  # Without other patches
  for patch in "${patches[@]}"; do
    repo="${patch%-*}" # 'joomla-cms', 'database' or 'joomla-cypress'
    if [[ "$repo" = "joomla-cms" || "$repo" = "database" ]]; then
      help
      error "Patching 'installation/joomla-cypress' cannot be combined with '${patch}'."
      exit 1
    fi
  done

  # Use the first Joomla docker instance for working with Git
  instance=${allInstalledInstances[0]}

  for patch in "${patches[@]}"; do
    log "installation/joomla-cypress – Starting with PR '${patch}'"
    patch_number="${patch##*-}" # e.g. 31
    current_branch=$(docker exec "jbt-${instance}" bash -c "cd /jbt/installation/joomla-cypress && git branch --show-current")
    # Case 1: joomla-cypress is already Git cloned, only to create merge branch first time
    if [ "${current_branch}" != "${merge_branch}" ]; then
      log "installation/joomla-cypress – Create '${merge_branch}' branch and switch to it"
      docker exec "jbt-${instance}" bash -c "cd /jbt/installation/joomla-cypress && git checkout -b ${merge_branch}"
    fi
    # Case 2: Check if the patch has already been applied in existing Git repository.
    # TODO: ?Needed? check PR is already included in the release
    if docker exec "jbt-${instance}" bash -c "
        cd /jbt/installation/joomla-cypress
        git fetch origin \"pull/${patch_number}/head:jbt-pr-${patch_number}\"
        git merge-base --is-ancestor \"jbt-pr-${patch_number}\" \"${merge_branch}\""; then
          log "installation/joomla-cypress  – PR '${patch}' has already been applied"
      continue
    else 
      # Case 3: Apply the patch to the existing Git repository
      # Using a simple Git merge (instead of a three-way diff) to apply the specific PR differences between
      # the two branches. This may introduce additional changes, but ensures the merge is possible.
      log "installation/joomla-cypress – Apply PR ${patch}"
      docker exec "jbt-${instance}" bash -c "cd /jbt/installation/joomla-cypress && git merge \"jbt-pr-${patch_number}\""
    fi
  done
  exit 0
fi

# If no instance was given, use all.
if [ ${#instancesToPatch[@]} -eq 0 ]; then
  instancesToPatch=("${allInstalledInstances[@]}")
fi

# Patching Joomla instance
for instance in "${instancesToPatch[@]}"; do
  for patch in "${patches[@]}"; do
    repo="${patch%-*}" # 'joomla-cms', 'database' or 'joomla-cypress'
    patch_number="${patch##*-}" # e.g. 43968, 31 or 33

    log "jbt-${instance} – Starting with PR '${patch}'"

    if [ "${repo}" = "joomla-cms" ]; then
      if [ -f "joomla-${instance}/.git/shallow" ]; then
        # Unshallow 'joomla-cms' as it was cloned with --depth 1 in setup.sh for speed and space
        log "jbt-${instance} – Git unshallow '${repo}' repository"
        docker exec "jbt-${instance}" git fetch --unshallow
      fi
      repo_version=$(grep '"version":' "joomla-${instance}/package.json" | sed -n 's/.*"version": "\([0-9.]*\)".*/\1/p')
      dir="."
      current_branch=$(docker exec "jbt-${instance}" bash -c "git branch --show-current")
      if [ "${current_branch}" != "${merge_branch}" ]; then
        log "jbt-${instance} – Create '${merge_branch}' branch on 'joomla-cms' repository and switch to it"
        docker exec "jbt-${instance}" git checkout -b "${merge_branch}"
      fi
    elif [ "${repo}" = "database" ]; then
      dir="libraries/vendor/joomla/joomla-framework"
      repo_version=$(docker exec "jbt-${instance}" bash -c "composer info joomla/database| grep versions | sed 's/versions : \* //'")
    elif [ "${repo}" = "joomla-cypress" ]; then
      dir="node_modules/joomla-projects"
      repo_version=$(docker exec "jbt-${instance}" bash -c "npm list joomla-cypress | grep 'joomla-cypress@' | sed 's/.*joomla-cypress@//'")
    else
      error "Repository '${repo}' is not supported, '${patch}' patch will be ignored."
      continue
    fi

    #      dir is '.', 'libraries/vendor/joomla/joomla-framework' or 'node_modules/joomla-projects'
    # base_dir is '.', 'libraries/vendor/joomla'                  or 'node_modules'
    basedir=$(dirname "${dir}")

    # Case 0: Directory doesn't exist (don't check for joomla-cms)
    if [ "${repo}" != "joomla-cms" ] && [ ! -d "joomla-${instance}/${basedir}/${repo}" ]; then
      error "Missing 'joomla-${instance}/${basedir}/${repo}' directory, '${patch}' patch will be ignored."
      continue
    fi

    # Case 1: Clone to new Git repository and apply the patch (never for joomla-cms)
    if [ "${repo}" != "joomla-cms" ] && [ ! -d "joomla-${instance}/${basedir}/${repo}/.git" ]; then
      log "jbt-${instance} – Delete 'joomla-${instance}/${basedir}/${repo}' directory"
      rm -rf "joomla-${instance}/${basedir}/${repo}" 2>/dev/null || sudo rm -rf "joomla-${instance}/${basedir}/${repo}"
      log "jbt-${instance} – Git clone $(basename "${dir}")/${repo}, version ${repo_version}"
      docker exec "jbt-${instance}" bash -c "
        cd ${basedir}
        git clone \"https://github.com/$(basename "${dir}")/${repo}\"
        cd ${repo}
        git checkout -b \"${merge_branch}\" \"refs/tags/${repo_version}\""
      # Merge given PR
      log "jbt-${instance} – Apply PR ${patch}"
      # Using a simple Git merge (instead of a three-way diff) to apply the specific PR differences between
      # the two branches. This may introduce additional changes, but ensures the merge is possible.
      docker exec "jbt-${instance}" bash -c "
        cd \"${basedir}/${repo}\"
        git fetch origin \"pull/${patch_number}/head:jbt-pr-${patch_number}\"
        git merge \"jbt-pr-${patch_number}\"
        git config --global --add safe.directory \"/var/www/html/${basedir}/${repo}\""
      continue
    elif
      # Case 2: Check if the patch has already been applied in existing Git repository.
      # TODO: ?Needed? check PR is already included in the release
      docker exec "jbt-${instance}" bash -c "
        [ \"${repo}\" != \"joomla-cms\" ] && cd \"${basedir}/${repo}\"
        git fetch origin \"pull/${patch_number}/head:jbt-pr-${patch_number}\"
        git merge-base --is-ancestor \"jbt-pr-${patch_number}\" \"${merge_branch}\""; then
          log "jbt-${instance} – PR '${patch}' has already been applied"
      continue
    else
      # Case 3: Apply the patch to the existing Git repository
      # Using a simple Git merge (instead of a three-way diff) to apply the specific PR differences between
      # the two branches. This may introduce additional changes, but ensures the merge is possible.
      log "jbt-${instance} – Apply PR ${patch}"
      docker exec "jbt-${instance}" bash -c "
        [ \"${repo}\" != \"joomla-cms\" ] && cd \"${basedir}/${repo}\"
        git merge \"jbt-pr-${patch_number}\""
      continue
    fi
  done
done
