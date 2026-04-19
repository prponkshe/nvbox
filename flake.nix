{
  description = "Thin wrapper: run devcontainer with host tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        run = pkgs.writeShellScriptBin "run-devcontainer-nix" ''
          set -euo pipefail

          REPO_DIR="''${1:-.}"
          REPO_DIR="$(cd "$REPO_DIR" && pwd)"
          HOST_NVIM_CONFIG="$HOME/.config/nvim"
          HOST_SSH_CONFIG="$HOME/.ssh"

          require() {
            if ! command -v "$1" >/dev/null 2>&1; then
              echo "ERROR: missing required command: $1" >&2
              echo "Install it on your host. This flake will not provide it." >&2
              exit 1
            fi
          }

          require docker
          require devcontainer
          require bash
          require curl

          if [ -f "$REPO_DIR/.devcontainer/devcontainer.json" ]; then
            DEVCONTAINER_CONFIG="$REPO_DIR/.devcontainer/devcontainer.json"
          else
            DEVCONTAINER_CONFIG="$REPO_DIR/devcontainer.json"
          fi

          if [ ! -f "$REPO_DIR/.devcontainer/devcontainer.json" ] && [ ! -f "$REPO_DIR/devcontainer.json" ]; then
            echo "ERROR: no devcontainer.json found in:" >&2
            echo "  $REPO_DIR/.devcontainer/devcontainer.json" >&2
            echo "  $REPO_DIR/devcontainer.json" >&2
            exit 1
          fi

          echo "[1/5] build"
          devcontainer build --workspace-folder "$REPO_DIR"

          echo "[2/5] up"
          devcontainer up --workspace-folder "$REPO_DIR" --skip-post-create

          CONTAINER_ID="$(
            docker ps -q \
              --filter "label=devcontainer.local_folder=$REPO_DIR" \
              --filter "label=devcontainer.config_file=$DEVCONTAINER_CONFIG" \
              | head -n 1
          )"

          if [ -z "$CONTAINER_ID" ]; then
            echo "ERROR: could not determine devcontainer container ID" >&2
            exit 1
          fi

          echo "[3/6] install nix"
          devcontainer exec --workspace-folder "$REPO_DIR" bash -lc '
            set -euo pipefail

            if command -v nix >/dev/null 2>&1; then
              echo "nix already installed"
              exit 0
            fi

            export DEBIAN_FRONTEND=noninteractive

            if command -v apt-get >/dev/null 2>&1; then
              apt-get update
              apt-get install -y curl xz-utils sudo ca-certificates
            fi

            curl -L https://nixos.org/nix/install -o /tmp/install-nix.sh
            sh /tmp/install-nix.sh --daemon --yes
          '

          echo "[4/6] install neovim"
          devcontainer exec --workspace-folder "$REPO_DIR" bash -lc '
            set -euo pipefail

            if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
              . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
            elif [ -e /etc/profile.d/nix.sh ]; then
              . /etc/profile.d/nix.sh
            fi

            nix --extra-experimental-features "nix-command flakes" profile install nixpkgs#neovim nixpkgs#ripgrep
          '

          echo "[5/6] copy nvim config"
          if [ -e "$HOST_NVIM_CONFIG" ]; then
            CONTAINER_METADATA="$(
              devcontainer exec --workspace-folder "$REPO_DIR" bash -lc '
                set -euo pipefail
                printf "CONTAINER_USER=%s\n" "$(id -un)"
                printf "CONTAINER_UID=%s\n" "$(id -u)"
                printf "CONTAINER_GID=%s\n" "$(id -g)"
                printf "CONTAINER_HOME=%s\n" "$HOME"
              '
            )"

            eval "$CONTAINER_METADATA"

            docker exec "$CONTAINER_ID" sh -lc 'mkdir -p "$1/.config"' sh "$CONTAINER_HOME"
            docker cp -L "$HOST_NVIM_CONFIG" "$CONTAINER_ID:$CONTAINER_HOME/.config/"
            docker cp -L "$HOST_SSH_CONFIG" "$CONTAINER_ID:$CONTAINER_HOME/"
            docker exec "$CONTAINER_ID" chown -R "$CONTAINER_UID:$CONTAINER_GID" "$CONTAINER_HOME/.ssh"
            docker exec -u 0 "$CONTAINER_ID" sh -lc 'chown -R "$1:$2" "$3"' sh "$CONTAINER_UID" "$CONTAINER_GID" "$CONTAINER_HOME/.config/nvim"

            echo "copied $HOST_NVIM_CONFIG to $CONTAINER_USER:$CONTAINER_HOME/.config/nvim"
          else
            echo "skipping nvim config copy: $HOST_NVIM_CONFIG does not exist"
          fi

          echo "[6/6] shell"
          devcontainer exec --workspace-folder "$REPO_DIR" bash -lc '
            if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
              . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
            elif [ -e /etc/profile.d/nix.sh ]; then
              . /etc/profile.d/nix.sh
            fi
            exec bash -i
          '
        '';
      in
      {
        packages.default = run;

        apps.default = {
          type = "app";
          program = "${run}/bin/run-devcontainer-nix";
        };
      }
    );
}
