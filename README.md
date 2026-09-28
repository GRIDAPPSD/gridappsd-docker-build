# gridappsd/gridappsd_base container

This repository is used to build the base container for gridappsd.  

It also includes a few scripts one to create the releases and another to create a blazegraph container.



## Create a gridappsd release

`scripts/release/create_release.sh` creates a GitHub release tagged `v<VERSION>` in each
GridAPPS-D repository. Each release is made from the head of the repo's release branch and
its notes are GitHub's generated summary of changes since that repo's previous release
(What's Changed, New Contributors, Full Changelog), prefixed with a link to the readthedocs
release notes.

Requires the [GitHub CLI](https://cli.github.com/) authenticated with write access to the
repositories (`gh auth login`).

The script is a dry run unless `--execute` is given. The dry run checks every repository,
lists the commit and previous release for each, and prints the exact release notes that
would be published.

```
cd gridappsd-docker-build/scripts/release

# Preview (dry run) for the default repository list
./create_release.sh 2026.09.0

# Create the releases (asks for confirmation; add --yes to skip)
./create_release.sh --execute 2026.09.0

# Only specific repositories, optionally with the branch to release from
./create_release.sh 2026.09.0 gridappsd-viz gridappsd-docker:main
```

  - The default repository list is `DEFAULT_REPOS` at the top of the script. A repository
    given without `:branch` is released from its GitHub default branch.
  - Every repository is checked before anything is created; if any check fails, nothing is
    created.
  - Repositories where the `v<VERSION>` tag already exists are skipped, so a partially
    failed run can be rerun with the same command.
  - No release branches are created. Merge `develop` into each repository's release branch
    (`master`, `main`, or `gridappsd` for Powergrid-Models) before running; the dry run warns
    when `develop` has commits that are not in the release branch.
  - Docker images: creating the `v<VERSION>` tag triggers each repository's GitHub workflow,
    which builds and pushes its image as `:v<VERSION>`. The `gridappsd/blazegraph` image has
    no workflow, so the script copies `gridappsd/blazegraph:develop` (change with
    `--blazegraph-from TAG`, skip with `--no-blazegraph`) to `:v<VERSION>`, `:latest`,
    `:master` and `:main` on Docker Hub. This needs `docker buildx` and `docker login`.

## Build the blazegraph container

### 1.  Clone the build repository ###
```
git clone https://github.com/GRIDAPPSD/gridappsd-docker-build
```

### 2.  Create a virtual environment and install the python requirements ###
```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements_blazegraph.txt
```

### 3.  Run the create_release.sh script to create the local blazegraph container  ###
```
./create_blazegraph.sh
```
  - pulls the base lyrasis container
  - clones the GitHub repositories for the CIMHub and Powergrid0Models
  - imports the PowerGridModels/platform/ files, and inserts measurements and houses

### 4.  Verify the import was successfull ###
Review the bzbuild/build_timestamp/create.log file to verify all files, measurements, and houses were imported correctly.

