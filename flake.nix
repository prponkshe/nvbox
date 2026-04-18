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

          echo "[3/5] install nix"
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

          echo "[4/5] install neovim"
          devcontainer exec --workspace-folder "$REPO_DIR" bash -lc '
            set -euo pipefail

            if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
              . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
            elif [ -e /etc/profile.d/nix.sh ]; then
              . /etc/profile.d/nix.sh
            fi

            nix --extra-experimental-features "nix-command flakes" profile install nixpkgs#neovim
          '

          echo "[5/5] shell"
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
