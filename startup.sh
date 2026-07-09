#!/usr/bin/env bash

USER_HOME="${USER_HOME:-$HOME}"

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

create_dirs(){
	mkdir -p "$USER_HOME"/.config/git/ignore
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

compose_up() {
	docker compose -f compose-postgres.yml -f compose-services.yml up --detach
}

compose_down() {
	docker compose -f compose-postgres.yml -f compose-services.yml down
}

compose_status() {
	docker compose -f compose-postgres.yml -f compose-services.yml ps
}

print_usage() {
	cat <<'EOF'
Usage: ./startup.sh [OPTION]

Options:
  up       Start services (default)
  down     Stop services
	status   Show container status
  setup    Run setup only (plugin, dirs, network)
  help     Show this help
EOF
}


main() {
	local action="${1:-up}"
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

	case "$action" in
		up)
			setup_loki_plugin
			create_dirs
			ensure_devel_repo_path "$script_dir"
			create_temporal_network
			compose_up
			echo "Services started."
			compose_status
			;;
		down)
			compose_down
			;;
		status)
			compose_status
			;;
		setup)
			setup_loki_plugin
			create_dirs
			ensure_devel_repo_path "$script_dir"
			create_temporal_network
			echo "Setup complete."
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
