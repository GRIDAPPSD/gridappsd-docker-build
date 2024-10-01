#!/bin/bash

VERSION="2024.06.0"

user="YOURGITHUBUSERNAME"
TOKEN="YOURGITHUBTOKEN"

OWNER="GRIDAPPSD"
gh="https://github.com/gridappsd/"

repos="GOSS-GridAPPS-D gridappsd-viz gridappsd-sample-app proven-docker gridappsd-docker-build gridappsd-data gridappsd-python:main Powergrid-Models:gridappsd gridappsd-sensor-simulator gridappsd-testing gridappsd-docker:main gridappsd-sample-distributed-app:main"
repos="GOSS-GridAPPS-D gridappsd-viz gridappsd-sample-app proven-docker gridappsd-docker-build gridappsd-data                  Powergrid-Models:gridappsd gridappsd-sensor-simulator gridappsd-testing gridappsd-docker:main gridappsd-sample-distributed-app:main"

release_blazegraph=true
#release_blazegraph=false

VERSIONU=$(echo $VERSION | sed 's/\./-/'g)

list_pr() {
  myrepo=$1
  #list open pull requests
  echo "XXXX"
  echo "$myrepo"
  echo "curl -s https://api.github.com/repos/${OWNER}/$myrepo/pulls  | jq '.[] | {head: .head.label, base: .base.label, url: .url, updated: .updated_at}'"
  curl -s https://api.github.com/repos/${OWNER}/$myrepo/pulls  | jq '.[] | {head: .head.label, base: .base.label, url: .url, updated: .updated_at}'
  echo " "
} 

create_release_branch() {
  myrepo=$1
  # Create the release/$VERSION from develop
  if [ ! -d release_$VERSION ]; then
     mkdir release_$VERSION
  else
    echo "Directory already exists release_$VERSION"
    #exit 1
  fi
  cd release_$VERSION
  if [ ! -d $myrepo ]; then
    git clone ${gh}$myrepo -b develop
    cd $myrepo
    git checkout -b releases/$VERSION

    if [ "$myrepo" == "gridappsd-docker" ]; then
      sed -i'.bak' "s/^GRIDAPPSD_TAG=':develop'/GRIDAPPSD_TAG=':v$VERSION'/" run.sh
      rm run.sh.bak
      git add run.sh
      git commit -m "Updated default version for release: $VERSION"
    fi

    #echo "Pushing new release version"
    git push -u origin releases/$VERSION
    cd ..
  else
    echo "Repo $myrepo exists, skipping"
  fi
  cd ..
}

create_pull_request() {
  myrepo=$1
  mybranch=$2
  # From the releases/$VERSION branch, create the pull request to main
  #"title":"testPR","base":"main", "head":"user-repo:main"
  API_JSON=$(printf '{"title": "Release of version %s", "body": "Release of version %s", "head": "%s:releases/%s", "base": "%s"}' $VERSION $VERSION $OWNER $VERSION $mybranch)
  echo "curl -u ${user}:${TOKEN} --data \"$API_JSON\" https://api.github.com/repos/${OWNER}/$myrepo/pulls"
  curl -u ${user}:${TOKEN} --data "$API_JSON" https://api.github.com/repos/${OWNER}/$myrepo/pulls
}

create_release() {
  myrepo=$1
  mybranch=$2
  if [ `list_pr $myrepo | grep -c release` -gt 0 ]; then
    echo "Exiting, open release pull requests $myrepo"
      list_pr $myrepo | grep release
    exit 1
  else
    API_JSON=$(printf '{"tag_name": "v%s", "target_commitish": "%s", "name": "%s release", "body": "See https://gridappsd.readthedocs.io/en/master/overview/index.html#version-%s for release notes.","draft": false,"prerelease": false}' $VERSION $mybranch $VERSION $VERSIONU)
    echo "curl -u ${user}:${TOKEN} --data \"$API_JSON\" https://api.github.com/repos/${OWNER}/$myrepo/releases"
    curl -u ${user}:${TOKEN} --data "$API_JSON" https://api.github.com/repos/${OWNER}/$myrepo/releases
  fi
}

create_beta_release() {
  myrepo=$1
  if [ `list_pr $myrepo | grep -c release` -gt 0 ]; then
    echo "Exiting, open release pull requests $myrepo"
    list_pr $myrepo | grep release
    exit 1
  else
    API_JSON=$(printf '{"tag_name": "v%s", "target_commitish": "develop", "name": "%s release", "body": "See https://gridappsd.readthedocs.io/en/master/overview/index.html#version-%s for release notes.","draft": false,"prerelease": false}' $VERSION $VERSION $VERSIONU)
    echo "curl -u ${user}:${TOKEN} --data \"$API_JSON\" https://api.github.com/repos/${OWNER}/$myrepo/releases"
    curl -u ${user}:${TOKEN} --data "$API_JSON" https://api.github.com/repos/${OWNER}/$myrepo/releases
  fi
}

release_status=".${VERSION}.status"

#for repository in $repos; do
  #branch=$(echo $repository | awk -F":" '{print $2}')
  #branch=${branch:=master}
  #repo=$(echo $repository | awk -F":" '{print $1}')
  #list open pull requests
#  list_pr $repo | grep -c "releases/$VERSION"
#done

#exit

if [ "$release_blazegraph" == true ]; then
  docker pull gridappsd/blazegraph:develop
fi

if [ ! -f $release_status ]; then
  status="Start"
else
  status=$(tail -1 $release_status)
fi

echo " "
echo "test: $status"
echo " "

case "$status" in
  "Start")
   
    echo "Step 1: Create the release/$VERSION from develop"
    for repository in $repos; do
      branch=$(echo $repository | awk -F":" '{print $2}')
      branch=${branch:=master}
      repo=$(echo $repository | awk -F":" '{print $1}')
      create_release_branch $repo $branch
    done
    if [ "$release_blazegraph" == true ]; then
      echo " "
      echo "Creating gridappsd/blazegraph:release_$VERSION"
      echo "docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:releases_$VERSION"
      docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:releases_$VERSION
      echo "docker push gridappsd/blazegraph:releases_$VERSION"
      docker push gridappsd/blazegraph:releases_$VERSION
    fi
    echo "Step1 Complete" > $release_status
    echo " "
    echo " "
    echo "Verify containers were built and "
    echo "test the:releases_$VERSION version before running the next step"
    echo "./run.sh -t releases_$VERSION"
    ;;
  "Step1 Complete")
    echo "Step 2: From the releases/$VERSION branch, create the pull requests to the main branch"
    for repository in $repos; do
      branch=$(echo $repository | awk -F":" '{print $2}')
      branch=${branch:=master}
      repo=$(echo $repository | awk -F":" '{print $1}')
      create_pull_request $repo $branch
    done
    if [ "$release_blazegraph" == true ]; then
      echo " "
      echo "Creating gridappsd/blazegraph:main"
      echo "docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:main"
      echo "docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:master"
      docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:main
      echo "docker push gridappsd/blazegraph:main"
      echo "docker push gridappsd/blazegraph:master"
      docker push gridappsd/blazegraph:main
    fi
    echo "Step2 Complete" > $release_status
    echo " "
    echo " "
    echo "Assign and close the pull requests before running the next step"
    ;; 
  "Step2 Complete")
    echo "Step 3: After the pull request's are approved then create the Tagged Releases"
    for repository in $repos; do
      branch=$(echo $repository | awk -F":" '{print $2}')
      branch=${branch:=master}
      repo=$(echo $repository | awk -F":" '{print $1}')
      if [ $(list_pr $repo | grep -c "releases/$VERSION") -gt 0 ]; then
        echo "Error: there are open pull requests for $repo releases/$VERSION"
        list_pr $repo | grep "releases/$VERSION"
        exit 1
      fi
    done
    for repository in $repos; do
      branch=$(echo $repository | awk -F":" '{print $2}')
      branch=${branch:=master}
      repo=$(echo $repository | awk -F":" '{print $1}')
      create_release $repo $branch
    done
    if [ "$release_blazegraph" == true ]; then
      echo " "
      echo "Creating gridappsd/blazegraph:v$VERSION"
      docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:v$VERSION
      echo "docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:v$VERSION"
      docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:latest
      echo "docker tag gridappsd/blazegraph:develop gridappsd/blazegraph:latest"
      docker push gridappsd/blazegraph:latest
      echo "docker push gridappsd/blazegraph:v$VERSION"
      docker push gridappsd/blazegraph:v$VERSION
    fi
    echo "Step3 Complete" > $release_status
    #####create_beta_release $repo
    echo " "
    echo " "
    echo "Release complete"
    echo "Verify containers were built and "
    echo "test the:v$VERSION version"
    echo "./run.sh -t v$VERSION"
    ;;
  *)
      echo "Something didn't work correctly"
      exit 1
esac






