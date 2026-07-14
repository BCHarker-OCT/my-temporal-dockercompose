#!/usr/bin/env bash

USER_HOME="${USER_HOME:-$HOME}"
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SINGLE_PROJECT_NAME="${SINGLE_PROJECT_NAME:-temporal-single}"
REPLICATION_PROJECT_NAME="${REPLICATION_PROJECT_NAME:-temporal-replication}"
LEGACY_PROJECT_NAME="${LEGACY_PROJECT_NAME:-$(basename "$SCRIPT_ROOT")}"

SINGLE_STACK_FILES=(-f compose-postgres.yml -f compose-services.yml)
REPLICATION_STACK_FILES=(-f compose-services-replication.yml)

setup_loki_plugin() {
	if ! docker plugin ls --format '{{.Name}}' | grep -Eq '^loki(:latest)?$'; then
		docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
		echo "Loki plugin installed."
	else
		echo "Loki plugin already configured."
	fi
}

create_temporal_network() {
    	if ! docker network inspect temporal-network >/dev/null 2>&1; then
    		docker network create temporal-network
    	fi
}

create_replication_network() {
	if ! docker network inspect temporal-network-replication >/dev/null 2>&1; then
		docker network create temporal-network-replication
	fi
}

create_dirs(){
	mkdir -p "$USER_HOME"/devel/temporal/temporal
	mkdir -p "$USER_HOME"/devel/temporal-etcd-dynconfig
}

ensure_devel_repo_path() {
	local script_dir="$1"
	local target="$USER_HOME/devel/my-temporal-dockercompose"

	if [ "$script_dir" = "$target" ]; then
		echo "Repo path ready: $target"
		return
	fi

	if [ -L "$target" ]; then
		rm "$target"
	fi

	if [ -e "$target" ] && [ ! -d "$target" ]; then
		echo "Repo path exists and is not directory: $target"
		echo "Please fix path and retry."
		return
	fi

	mkdir -p "$target"

	if command -v rsync >/dev/null 2>&1; then
		rsync -a --delete --exclude '.git' "$script_dir"/ "$target"/
	else
		cp -R "$script_dir"/. "$target"/
	fi

	echo "Repo synced: $script_dir -> $target"
}

compose_single_up() {
	docker compose -p "$SINGLE_PROJECT_NAME" "${SINGLE_STACK_FILES[@]}" up --detach
}

compose_single_down() {
	docker compose -p "$SINGLE_PROJECT_NAME" "${SINGLE_STACK_FILES[@]}" down --remove-orphans "$@"
	docker compose -p "$LEGACY_PROJECT_NAME" "${SINGLE_STACK_FILES[@]}" down --remove-orphans "$@" >/dev/null 2>&1 || true
}

compose_single_status() {
	docker compose -p "$SINGLE_PROJECT_NAME" "${SINGLE_STACK_FILES[@]}" ps
}

compose_replication_up() {
	docker compose -p "$REPLICATION_PROJECT_NAME" "${REPLICATION_STACK_FILES[@]}" up --detach
}

compose_replication_down() {
	docker compose -p "$REPLICATION_PROJECT_NAME" "${REPLICATION_STACK_FILES[@]}" down --remove-orphans "$@"
	docker compose -p "$LEGACY_PROJECT_NAME" "${REPLICATION_STACK_FILES[@]}" down --remove-orphans "$@" >/dev/null 2>&1 || true
}

compose_replication_status() {
	docker compose -p "$REPLICATION_PROJECT_NAME" "${REPLICATION_STACK_FILES[@]}" ps
}

validate_stack() {
	case "$1" in
		single|replication|both)
			return 0
			;;
		*)
			echo "Unknown stack: $1"
			print_usage
			return 1
			;;
	esac
}

stack_setup() {
	local stack="$1"

	setup_loki_plugin
	create_dirs
	ensure_devel_repo_path "$2"

	case "$stack" in
		single)
			create_temporal_network
			;;
		replication)
			create_replication_network
			;;
		both)
			create_temporal_network
			create_replication_network
			;;
	esac
}

stack_up() {
	case "$1" in
		single)
			compose_single_up
			;;
		replication)
			compose_replication_up
			;;
		both)
			compose_single_up
			compose_replication_up
			;;
	esac
}

stack_down() {
	local stack="$1"
	shift

	case "$stack" in
		single)
			compose_single_down "$@"
			;;
		replication)
			compose_replication_down "$@"
			;;
		both)
			compose_replication_down "$@"
			compose_single_down "$@"
			;;
	esac
}

stack_status() {
	case "$1" in
		single)
			compose_single_status
			;;
		replication)
			compose_replication_status
			;;
		both)
			compose_single_status
			compose_replication_status
			;;
	esac
}

print_usage() {
	cat <<'EOF'
Usage: ./startup.sh [OPTION]

Options:
  up [stack]         Start services (default stack: single)
  down [stack]       Stop services
  recreate [stack]   Recreate services with docker compose down -v first
  status [stack]     Show container status
  setup [stack]      Run setup only (plugin, dirs, network)
  help     Show this help

Stacks:
  single       Single-cluster stack (default)
  replication  Two-cluster replication stack
  both         Single-cluster and replication stacks
EOF
}


main() {
	local action="${1:-up}"
	local stack="${2:-single}"
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

	if [ "$action" != "help" ] && [ "$action" != "-h" ] && [ "$action" != "--help" ]; then
		validate_stack "$stack" || return 1
	fi

	case "$action" in
		up)
			stack_setup "$stack" "$script_dir"
			stack_up "$stack"
			echo "Services started for stack: $stack"
			stack_status "$stack"
			;;
		down)
			stack_down "$stack"
			;;
		recreate)
			stack_down "$stack" -v
			stack_setup "$stack" "$script_dir"
			stack_up "$stack"
			echo "Services recreated for stack: $stack"
			stack_status "$stack"
			;;
		status)
			stack_status "$stack"
			;;
		setup)
			stack_setup "$stack" "$script_dir"
			echo "Setup complete for stack: $stack"
			;;
		help|-h|--help)
			print_usage
			;;
		*)
			echo "Unknown option: $action"
			print_usage
			return 1
			;;
	esac

}


main "$@"
