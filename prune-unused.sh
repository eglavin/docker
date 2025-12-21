#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
ASSUME_YES=false
PRUNE_IMAGES=true
PRUNE_VOLUMES=true
PRUNE_NETWORKS=true
PRUNE_BUILDER=false

usage() {
	cat <<EOF
Usage: $(basename "$0") [options]

Options:
	-n, --dry-run        Show what would be done (uses `docker system df` and lists)
	-y, --yes            Don't ask for confirmation (non-interactive)
	--no-images          Skip pruning images
	--no-volumes         Skip pruning volumes
	--no-networks        Skip pruning networks
	--builder            Also prune build cache (docker builder prune)
	-h, --help           Show this help

Examples:
	$(basename "$0")          # interactively prune images, volumes, networks
	$(basename "$0") -n       # dry-run
	$(basename "$0") --no-images  # prune volumes and networks only
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-n|--dry-run) DRY_RUN=true; shift;;
		-y|--yes) ASSUME_YES=true; shift;;
		--no-images) PRUNE_IMAGES=false; shift;;
		--no-volumes) PRUNE_VOLUMES=false; shift;;
		--no-networks) PRUNE_NETWORKS=false; shift;;
		--builder) PRUNE_BUILDER=true; shift;;
		-h|--help) usage; exit 0;;
		*) echo "Unknown option: $1" >&2; usage; exit 2;;
	esac
done

command -v docker >/dev/null 2>&1 || { echo "docker CLI not found in PATH." >&2; exit 1; }

if ! docker info >/dev/null 2>&1; then
	echo "Docker daemon not accessible. Is Docker running?" >&2
	exit 1
fi

show_dry_run() {
	echo "---- docker system df ----"
	docker system df || true

	if $PRUNE_IMAGES; then
		echo
		echo "---- Dangling images (candidate for removal) ----"
		docker images --filter "dangling=true" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" || true
	fi

	if $PRUNE_VOLUMES; then
		echo
		echo "---- Volumes ----"
		docker volume ls || true
	fi

	if $PRUNE_NETWORKS; then
		echo
		echo "---- User networks (non-default) ----"
		docker network ls --filter "type=custom" || true
	fi

	if $PRUNE_BUILDER; then
		echo
		echo "---- Builder cache summary ----"
		docker builder prune --filter "until=24h" --all --force --filter "label!=keep" --help >/dev/null 2>&1 || true
		echo "(Builder prune will clear build cache when executed.)"
	fi
}

confirm() {
	if $ASSUME_YES; then
		return 0
	fi
	read -r -p "Proceed with prune? [y/N] " ans
	case "$ans" in
		[yY]|[yY][eE][sS]) return 0 ;;
		*) echo "Aborted."; return 1 ;;
	esac
}

main() {
	if $DRY_RUN; then
		echo "DRY RUN: no changes will be made. Showing candidates and summary:"
		show_dry_run
		exit 0
	fi

	echo "About to prune the following types:"
	$PRUNE_IMAGES && echo " - images"
	$PRUNE_VOLUMES && echo " - volumes"
	$PRUNE_NETWORKS && echo " - networks"
	$PRUNE_BUILDER && echo " - builder cache"

	if ! confirm; then
		exit 0
	fi

	if $PRUNE_IMAGES; then
		echo "Pruning images..."
		docker image prune -a --force || true
	fi

	if $PRUNE_VOLUMES; then
		echo "Pruning volumes..."
		docker volume prune --force || true
	fi

	if $PRUNE_NETWORKS; then
		echo "Pruning networks..."
		docker network prune --force || true
	fi

	if $PRUNE_BUILDER; then
		echo "Pruning build cache..."
		docker builder prune --all --force || true
	fi

	echo "Prune completed. Summary:"
	docker system df || true
}

main

