# devcontainer-nvim

`devcontainer-nvim` is a small Nix flake that bootstraps a devcontainer, installs Nix inside it if needed, installs a current `neovim` from `nixpkgs`, copies the host Neovim config into the container user's home, and opens an interactive shell in the container.

## Motivation

This exists for a specific workflow: using Neovim inside devcontainers that are common in corporate development environments.

In practice, many teams standardize on VS Code devcontainers, but the underlying images are often pinned to older distributions for stability, compatibility, or policy reasons. That makes it awkward to run a recent Neovim entirely inside the container, especially when the base image does not provide the system support expected by newer upstream binaries.

Host-side workarounds are not a good fit for this use case. In particular, external `clangd`-based setups lose one of the main advantages of editing inside the container: language servers can no longer reliably see the same libraries, headers, and toolchain state that the build sees inside the devcontainer, including paths such as `/usr/lib` and `/usr/include`.

This flake takes a narrow approach:

- keep the existing devcontainer workflow
- install Nix inside the container
- install a recent `neovim` from `nixpkgs`
- copy the host `~/.config/nvim` into the container user's `~/.config`
- run Neovim where the project environment already exists

If you are not already heavily invested in Neovim, Zed is a strong alternative. This repository is mainly for the case where the preferred editor is still Neovim and the container image is the limiting factor.

## What It Does

Running the app performs these steps:

1. Build the devcontainer.
2. Start the devcontainer.
3. Install Nix inside the container if it is missing.
4. Install `neovim` from `nixpkgs`.
5. Copy the host `~/.config/nvim` into the container user's `~/.config`.
6. Open an interactive shell inside the container.

The flake is intentionally thin. It does not provide Docker, the Dev Container CLI, or other host tooling.

## Requirements

The host system must provide:

- `docker`
- `devcontainer`
- `bash`
- `curl`
- `nix` with flake support

The target project must contain one of:

- `.devcontainer/devcontainer.json`
- `devcontainer.json`

## Installing Nix on Non-NixOS

If Nix is not already installed on the host, install it with the official installer:

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Then enable flakes by adding this line to `/etc/nix/nix.conf`:

```conf
experimental-features = nix-command flakes
```

After updating `nix.conf`, restart the Nix daemon or open a new shell session before running `nix run`.

## Usage

Run the flake against a project containing a devcontainer configuration:

```bash
nix run . -- /path/to/project
```

To run it against the current directory:

```bash
nix run . -- .
```

After the setup completes, an interactive shell is opened inside the container. Start Neovim with:

```bash
nvim
```

## Usage Steps

1. Install the host dependencies: `docker`, `devcontainer`, `bash`, `curl`, and `nix`.
2. Ensure the target repository contains `.devcontainer/devcontainer.json` or `devcontainer.json`.
3. If the host is not NixOS and Nix is not installed yet, run `sh <(curl -L https://nixos.org/nix/install) --daemon`.
4. Add `experimental-features = nix-command flakes` to `/etc/nix/nix.conf`.
5. Open a new shell session, or restart the Nix daemon if needed.
6. Clone this repository or otherwise make the flake available locally.
7. Run `nix run . -- /path/to/project` from this repository.
8. Wait for the script to build the container, start it, install Nix, install `neovim`, and copy `~/.config/nvim` into the container.
9. Use the interactive shell opened inside the container and launch `nvim`.

## Why Not Host-Side `clangd`

For container-heavy C and C++ workflows, running the editor or language server outside the container is usually the wrong boundary.

The container filesystem often contains the effective development environment:

- libraries under `/usr/lib`
- headers under `/usr/include`
- container-specific toolchains
- distribution-provided build dependencies

Once language tooling moves outside that environment, editor behavior starts to diverge from the actual build context. This flake prefers running Neovim inside the same environment the project is built in.

## Compatibility

- Currently tested only with Debian-based devcontainers.
- Extensively used with Ubuntu 20.04-based devcontainers.
- Assumes `apt-get` is available when Nix must be installed inside the container.

## Scope

This repository does not try to solve full editor provisioning, general dotfiles management, or plugin setup. It only provides a small wrapper around an existing devcontainer workflow so that a recent Neovim can run inside the container with a copied host `~/.config/nvim`.
