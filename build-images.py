#!/usr/bin/env python3
"""
Build script for GridAPPS-D Docker images.

This script replicates the functionality of build-images.sh with enhanced
command-line argument support and additional options.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


def run_command(cmd, cwd=None, env=None, check=True):
    """Run a shell command and return the result."""
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)

    print(f"Running: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    result = subprocess.run(
        cmd,
        cwd=cwd,
        env=merged_env,
        shell=isinstance(cmd, str),
        check=check,
        capture_output=False
    )
    return result


def clone_or_update_repo(repo_name, org, branch, script_dir, github_host="github.com"):
    """Clone a repository or update it if it already exists."""
    repo_path = script_dir / repo_name
    uri = f"https://{github_host}/{org}/{repo_name}.git"

    print("================================")
    print(f"Cloning/Updating {repo_name}")
    print(f"  Org: {org}")
    print(f"  Branch: {branch}")
    print(f"  URI: {uri}")
    print("================================")

    if repo_path.exists():
        run_command(["git", "fetch", "origin"], cwd=repo_path)
        run_command(["git", "reset", "--hard"], cwd=repo_path)
        run_command(["git", "checkout", branch], cwd=repo_path)
        run_command(["git", "reset", "--hard", f"origin/{branch}"], cwd=repo_path)
    else:
        run_command(["git", "clone", "-b", branch, uri, str(repo_path)])


def build_docker_image(dockerfile, tag, context, build_args=None, no_cache=False, network="host"):
    """Build a Docker image."""
    cmd = ["docker", "build"]

    if no_cache:
        cmd.append("--no-cache")

    if network:
        cmd.extend(["--network", network])

    if build_args:
        for key, value in build_args.items():
            cmd.extend(["--build-arg", f"{key}={value}"])

    cmd.extend(["-f", str(dockerfile), "-t", tag, str(context)])

    run_command(cmd)


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Build GridAPPS-D Docker images",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Build with default settings (requires branch arguments)
  %(prog)s --goss-branch develop --gridappsd-branch develop

  # Build with a specific tag
  %(prog)s --goss-branch develop --gridappsd-branch develop --tag v2025.01.0

  # Build from a fork
  %(prog)s --goss-org myuser --goss-branch feature-x --gridappsd-org myuser --gridappsd-branch feature-x

  # Build only specific images
  %(prog)s --goss-branch develop --gridappsd-branch develop --images base gridappsd

  # Skip repository updates
  %(prog)s --goss-branch develop --gridappsd-branch develop --skip-clone

  # Build with no cache
  %(prog)s --goss-branch develop --gridappsd-branch develop --no-cache
        """
    )

    # Repository configuration
    repo_group = parser.add_argument_group("Repository Options")
    repo_group.add_argument(
        "--goss-org",
        default=os.environ.get("GOSS_ORG", "GRIDAPPSD"),
        help="GOSS repository GitHub organization (default: %(default)s)"
    )
    repo_group.add_argument(
        "--goss-branch",
        default=os.environ.get("GOSS_BRANCH"),
        required="GOSS_BRANCH" not in os.environ,
        help="GOSS branch to build (required, or set GOSS_BRANCH env var)"
    )
    repo_group.add_argument(
        "--gridappsd-org",
        default=os.environ.get("GRIDAPPSD_ORG", "GRIDAPPSD"),
        help="GOSS-GridAPPS-D repository GitHub organization (default: %(default)s)"
    )
    repo_group.add_argument(
        "--gridappsd-branch",
        default=os.environ.get("GRIDAPPSD_BRANCH"),
        required="GRIDAPPSD_BRANCH" not in os.environ,
        help="GOSS-GridAPPS-D branch to build (required, or set GRIDAPPSD_BRANCH env var)"
    )
    repo_group.add_argument(
        "--github-host",
        default=os.environ.get("GITHUB_HOST", "github.com"),
        help="GitHub host (default: %(default)s, use for GitHub Enterprise)"
    )
    repo_group.add_argument(
        "--skip-clone",
        action="store_true",
        help="Skip cloning/updating repositories (use existing local copies)"
    )

    # Image configuration
    image_group = parser.add_argument_group("Image Options")
    image_group.add_argument(
        "--tag", "-t",
        default=os.environ.get("GRIDAPPSD_TAG", ":develop"),
        help="Docker image tag (default: %(default)s)"
    )
    image_group.add_argument(
        "--images",
        nargs="+",
        choices=["base", "gridappsd", "viz", "all"],
        default=["all"],
        help="Which images to build (default: all)"
    )
    image_group.add_argument(
        "--registry",
        default="gridappsd",
        help="Docker registry/organization prefix (default: %(default)s)"
    )

    # Build configuration
    build_group = parser.add_argument_group("Build Options")
    build_group.add_argument(
        "--no-cache",
        action="store_true",
        help="Build images without using cache"
    )
    build_group.add_argument(
        "--network",
        default="host",
        help="Docker build network mode (default: %(default)s)"
    )
    build_group.add_argument(
        "--parallel",
        action="store_true",
        help="Enable parallel builds (requires BuildKit)"
    )
    build_group.add_argument(
        "--push",
        action="store_true",
        help="Push images to registry after building"
    )
    build_group.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without executing them"
    )

    # Dockerfile overrides
    dockerfile_group = parser.add_argument_group("Dockerfile Overrides")
    dockerfile_group.add_argument(
        "--dockerfile-base",
        default="Dockerfile.gridappsd_base",
        help="Dockerfile for base image (default: %(default)s)"
    )
    dockerfile_group.add_argument(
        "--dockerfile-gridappsd",
        default="Dockerfile.gridappsd",
        help="Dockerfile for gridappsd image (default: %(default)s)"
    )
    dockerfile_group.add_argument(
        "--dockerfile-viz",
        default="Dockerfile.gridappsd_viz",
        help="Dockerfile for viz image (default: %(default)s)"
    )

    # Verbosity
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output"
    )
    parser.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Suppress non-essential output"
    )

    return parser.parse_args()


def main():
    args = parse_args()

    # Ensure tag starts with colon if not empty and not already prefixed
    tag = args.tag
    if tag and not tag.startswith(":"):
        tag = f":{tag}"

    # Get script directory
    script_dir = Path(__file__).parent.resolve()

    # Set up Docker BuildKit environment
    build_env = {
        "DOCKER_BUILDKIT": "1",
        "BUILDKIT_PROGRESS": "plain" if not args.quiet else "auto"
    }

    # Determine which images to build
    images_to_build = set(args.images)
    if "all" in images_to_build:
        images_to_build = {"base", "gridappsd", "viz"}

    # Clone or update repositories
    if not args.skip_clone:
        clone_or_update_repo("GOSS", args.goss_org, args.goss_branch, script_dir, args.github_host)
        print()
        clone_or_update_repo("GOSS-GridAPPS-D", args.gridappsd_org, args.gridappsd_branch, script_dir, args.github_host)
        print()
    else:
        print("Skipping repository clone/update")
        print()

    built_images = []

    # Build base image
    if "base" in images_to_build:
        image_name = f"{args.registry}/gridappsd_base{tag}"
        print("================================")
        print("Building GridAPPS-D Base Image")
        print(f"Tag: {tag}")
        print("================================")

        if not args.dry_run:
            build_docker_image(
                dockerfile=script_dir / args.dockerfile_base,
                tag=image_name,
                context=script_dir,
                build_args={"GRIDAPPSD_TAG": tag},
                no_cache=args.no_cache,
                network=args.network
            )
        else:
            print(f"[DRY RUN] Would build: {image_name}")

        built_images.append(image_name)
        print()

    # Build gridappsd image
    if "gridappsd" in images_to_build:
        image_name = f"{args.registry}/gridappsd{tag}"
        print("================================")
        print("Building GridAPPS-D Application Image")
        print(f"Tag: {tag}")
        print("================================")

        if not args.dry_run:
            build_docker_image(
                dockerfile=script_dir / args.dockerfile_gridappsd,
                tag=image_name,
                context=script_dir,
                build_args={"GRIDAPPSD_VERSION_LABEL": tag},
                no_cache=args.no_cache,
                network=args.network
            )
        else:
            print(f"[DRY RUN] Would build: {image_name}")

        built_images.append(image_name)
        print()

    # Build viz image
    if "viz" in images_to_build:
        image_name = f"{args.registry}/viz{tag}"
        print("================================")
        print("Building GridAPPS-D Viz Image")
        print(f"Tag: {tag}")
        print("================================")

        if not args.dry_run:
            build_docker_image(
                dockerfile=script_dir / args.dockerfile_viz,
                tag=image_name,
                context=script_dir,
                build_args={"GRIDAPPSD_TAG": tag},
                no_cache=True,  # Viz always builds with no-cache in original script
                network=args.network
            )
        else:
            print(f"[DRY RUN] Would build: {image_name}")

        built_images.append(image_name)
        print()

    # Push images if requested
    if args.push and not args.dry_run:
        print("================================")
        print("Pushing Images to Registry")
        print("================================")
        for image in built_images:
            run_command(["docker", "push", image])
        print()
    elif args.push and args.dry_run:
        print("================================")
        print("[DRY RUN] Would push images:")
        for image in built_images:
            print(f"  - {image}")
        print("================================")
        print()

    # Print summary
    print("================================")
    print("Build Complete!")
    print("================================")
    print("Images built:")
    for image in built_images:
        print(f"  - {image}")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
