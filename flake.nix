{
  description = "Elitix — ClickHouse-first ELT orchestration platform";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Pinned older than the ld/cctools regression that crashes linking
    # cargo-watch on aarch64-darwin under current nixos-unstable (SIGTRAP in
    # cctools-binutils-darwin-wrapper). Only cargo-watch is sourced from this.
    nixpkgs-cargo-watch.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-cargo-watch, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
        pkgsCargoWatch = import nixpkgs-cargo-watch { inherit system; };

        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
	nodejs = pkgs.nodejs_26;
      in
      {

	formatter = pkgs.nixpkgs-fmt;
        devShells.default = pkgs.mkShell {
	  name = "datax";

          packages = with pkgs; [
            # Rust
            rustToolchain
	    openssl

	    sqlx-cli
	    pkgsCargoWatch.cargo-watch
	    cargo-audit
	    glab

	    nodejs
	    (corepack.override { nodejs-slim = nodejs; })
	    postgresql_17

	    # Native dev stack (no containers — avoids the Docker Desktop/colima
	    # VM penalty on macOS): process-compose supervises postgres/clickhouse/
	    # garage as raw binaries the same way docker-compose supervised them
	    # (deps, health/readiness gating, opt-in processes toggled on/off).
	    process-compose
	    garage_2

	    # docker-client/buildx stay for the prod/CI image (docker/elitix) and
	    # the Python-node sandbox (docker/python) — not part of the dev stack.
	    docker-client
	    docker-buildx
	    glab
	    fish
            clickhouse
	    mold
          ];

          nativeBuildInputs = with pkgs; [
            pkg-config
          ];

          env = {
	    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
	    RUST_SRC_PATH   = "${rustToolchain}/lib/rustlib/src/rust/library";
          };

          shellHook = ''
	    export COREPACK_HOME="$PWD/.nix-corepack";
	    export PATH="$COREPACK_HOME/bin:$PATH";
	    mkdir -p "$COREPACK_HOME/bin"
	    corepack enable --install-directory "$COREPACK_HOME/bin" pnpm >/dev/null
            exec fish
          '';
        };
      });
}
