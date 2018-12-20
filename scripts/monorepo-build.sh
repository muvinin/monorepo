#!/usr/bin/env bash
# vim: et sr sw=2 ts=2 smartindent:

# This file orchestrates the mono repo build process

set -x

NODE_BUILD_ENV_VERSION="node:10-slim"
STABLE_BRANCH="master"

docker run --rm \
  -v "$(pwd):/code" \
  -e PATH="/code/node_modules/.bin:$PATH" \
  -w /code \
  ${NODE_BUILD_ENV_VERSION} bash -c "npm install --production"

changed_packages=$(echo "{$(docker run --rm \
  -v "$(pwd):/code" \
  -e PATH="/code/node_modules/.bin:$PATH" \
  -w /code \
  ${NODE_BUILD_ENV_VERSION} \
  lerna changed --json --loglevel=silent | jq -c -r 'map(.name) | join(",")'),}")

echo "DEBUG changed_packages"
echo ${changed_packages}

if [ "$TRAVIS_EVENT_TYPE" == "pull_request" ]; then
  GIT_BRANCH=$TRAVIS_PULL_REQUEST_BRANCH;
  PR_VERSION_TAG="PR-$TRAVIS_PULL_REQUEST-$TRAVIS_BUILD_NUMBER"

elif [ -z $TRAVIS_TAG ]; then
  GIT_TAG=$TRAVIS_BRANCH
  GIT_BRANCH=$TRAVIS_BRANCH

else
  # This is master
  GIT_BRANCH=$TRAVIS_BRANCH;
fi


if [ ${changed_packages} = "{,}" ] || [ ${changed_packages} = "{}" ] || [ ${changed_packages} = {} ]
then
  echo "No packages were changed, nothing to build....if there was something to build put it in a package!!"
  exit 0
fi

# Bump all the versions in the monorepo for omega build, handles master and PR builds...at the moment we are doing this before we mount the files into the build container.
if [ "${GIT_BRANCH}" = "${STABLE_BRANCH}" ]
then
  echo ">>> Master version bump"
  git reset origin/${GIT_BRANCH} --hard

  git config user.email "ci@muvin.in"
  git config user.name "muvinin-ci-bot"
  git config --global push.default simple

  docker run --rm \
    -v "${HOME}/.npm:/root/.npm" \
    -v "$(pwd):/code" \
    -w /code \
    ${NODE_BUILD_ENV_VERSION} \
    npm run version:master

else
  echo ">>> Non-master version bump"
  docker run --rm \
    -v "${HOME}/.npm:/root/.npm" \
    -v "$(pwd):/code" \
    -w /code \
    ${NODE_BUILD_ENV_VERSION} \
    npm run version:pr
fi

# Push the tags and what has changed back to git remote if master build. Todo - pretty sure we can just do this when we do our lerna versioning.
if [ "${GIT_BRANCH}" = "${STABLE_BRANCH}" ]; then
  echo ">>> Master git publish"
  GIT_URL=$(echo ${GIT_URL} | sed -e 's/^https:\/\///g')
  # todo comment this back in to push master tags...
  git push https://${GITHUB_USER}:${GITHUB_PASS}@${GIT_URL}
  git push https://${GITHUB_USER}:${GITHUB_PASS}@${GIT_URL} --tags
else
  echo ">>> Non-master git push"
  echo "PR build changes, e.g. CHANGELOG.md are not pushed to origin."
fi

# Build and publish the packages that have changed...at the moment these use a build command that needs to be in each packages package.json.
docker run --rm \
  --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
  --mount type=bind,source=$(which docker),target=$(which docker) \
  -v "${HOME}/.docker/config.json:/root/.docker/config.json" \
  -v "${HOME}/.npm:/root/.npm" \
  -v "$(pwd):/code" \
  -w "/code" \
  -e HOST_WORKSPACE=$(pwd) \
  -e GIT_BRANCH=${GIT_BRANCH} \
  -e PR_VERSION_TAG=${PR_VERSION_TAG} \
  -e NODE_BUILD_ENV_VERSION=${NODE_BUILD_ENV_VERSION} \
  ${NODE_BUILD_ENV_VERSION} \
  /bin/bash -c \
  "export NODE_ENV=development npm run bootstrap && \
  lerna run --scope=${changed_packages} --include-filtered-dependencies publish && \
  lerna run deploy"
