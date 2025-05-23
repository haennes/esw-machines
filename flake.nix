{
  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs.url =
      "github:NixOS/nixpkgs";
    crane.url = "https://flakehub.com/f/ipetkov/crane/0.17.tar.gz";
    flake-utils.url = "github:gytis-ivaskevicius/flake-utils-plus";
  };

  outputs = { self, nixpkgs, crane, flake-utils}:
    let
      # read leptos options from `Cargo.toml`
      leptos-options = (builtins.fromTOML
        (builtins.readFile ./Cargo.toml)).package.metadata.leptos;
    in flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system ; };

        #cargo-leptos = (import ./nix/cargo-leptos.nix) {
        #  inherit pkgs craneLib;
        #  cargo-leptos = cargo-leptos-src;
        #};

        toolchain = pkgs.rust-bin.selectLatestNightlyWith (toolchain:
          toolchain.default.override {
            extensions = [ "rust-src" "rust-analyzer" ];
            targets = [ "wasm32-unknown-unknown" ];
          });

        src = ./.;

        craneLib = (crane.mkLib pkgs).overrideToolchain pkgs.rustc;

        common-args = {
          inherit src;

          # use the name defined in the `Cargo.toml` leptos options
          pname = leptos-options.output-name;
          version = "0.1.0";

          doCheck = false;

          nativeBuildInputs = [
            pkgs.clang
            pkgs.cargo
            pkgs.lld_19
            #pkgs.cargo-binutils
            #pkgs.rustc
            #pkgs.mold # faster compilation
            pkgs.binaryen # provides wasm-opt
          ] ++ pkgs.lib.optionals (system == "x86_64-linux") [
            #pkgs.nasm # wasm compiler only for x86_64-linux
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # Additional darwin specific inputs can be set here
            pkgs.libiconv # character encoding lib needed by darwin
          ];

          buildInputs = [
            pkgs.pkg-config # used by many crates for finding system packages
            # pkgs.openssl # needed for many http libraries
          ];

        };

        # build the deps for the frontend bundle, and export the target folder
        site-frontend-deps = craneLib.mkCargoDerivation (common-args // {
          pname = "site-frontend-deps";
          src = craneLib.mkDummySrc common-args;
          cargoArtifacts = null;
          doInstallCargoArtifacts = true;

          buildPhaseCargoCommand = ''
            cargo build \
              --package=${leptos-options.output-name} \
              --lib \
              --target-dir=/build/source/target/front \
              --target=wasm32-unknown-unknown \
              --no-default-features \
              --profile=${leptos-options.lib-profile-release}
          '';
        });

        # build the deps for the server binary, and export the target folder
        site-server-deps = craneLib.mkCargoDerivation (common-args // {
          pname = "site-server-deps";
          src = craneLib.mkDummySrc common-args;
          cargoArtifacts = site-frontend-deps;
          doInstallCargoArtifacts = true;

          buildPhaseCargoCommand = ''
            cargo build \
              --package=${leptos-options.output-name} \
              --no-default-features \
              --release
          '';
        });

        # build the binary and bundle using cargo leptos
        site-server = craneLib.buildPackage (common-args // {
          # add inputs needed for leptos build
          nativeBuildInputs = common-args.nativeBuildInputs ++ [
            #pkgs.cargo-leptos
            pkgs.cargo-leptos
            #pkgs.cargo
            # used by cargo-leptos for styling
            pkgs.dart-sass
            pkgs.tailwindcss
          ];

          # enable hash_files again
          buildPhaseCargoCommand = ''
            RUST_BACKTRACE=1 cargo leptos build --release -vvv
          '';
          #RUST_BACKTRACE=1 LEPTOS_HASH_FILES=true cargo leptos build --release -vvv

          installPhaseCommand = ''
            mkdir -p $out/bin
            cp target/release/esw-machines $out/bin/
            ##cp -r target/site-server $out/bin/
            #cp target/release/hash.txt $out/bin/
            cp -r target/site $out/bin/
            #cp -r content $out/bin/
          '';

          doCheck = false;
          cargoArtifacts = site-server-deps;
        });

        site-server-container = pkgs.dockerTools.buildLayeredImage {
          name = leptos-options.output-name;
          tag = "latest";
          contents = [ site-server ];
          config = {
            # we're not using tini here because we don't need to with
            #   fly.io's vm runner, because they use firecracker
            Cmd = [ "site-server" ];
            WorkingDir = "${site-server}/bin";
            # we provide the env variables that we get from Cargo.toml during
            #   development. these can be overridden when the container is run,
            #   but defaults are needed
            Env = [
              "LEPTOS_OUTPUT_NAME=${leptos-options.name}"
              "LEPTOS_SITE_ROOT=${leptos-options.name}"
              "LEPTOS_SITE_PKG_DIR=${leptos-options.site-pkg-dir}"
              "LEPTOS_SITE_ADDR=0.0.0.0:3000"
              # only used for user-defined things, like my cache headers on
              #   static files
              "LEPTOS_ENV=PROD"
              # this is set statically because I want this on only in prod;
              #   it breaks things in dev. I don't know why `1` doesn't work;
              #   it only picks it up if it's `true`
              "LEPTOS_HASH_FILES=true"
            ];
          };
        };

      in {
        ecks = {
          # lint packages
          app-hydrate-clippy = craneLib.cargoClippy (common-args // {
            cargoArtifacts = site-server-deps;
            cargoClippyExtraArgs =
              "-p site-app --features hydrate -- --deny warnings";
          });
          app-ssr-clippy = craneLib.cargoClippy (common-args // {
            cargoArtifacts = site-server-deps;
            cargoClippyExtraArgs =
              "-p site-app --features ssr -- --deny warnings";
          });
          site-server-clippy = craneLib.cargoClippy (common-args // {
            cargoArtifacts = site-server-deps;
            cargoClippyExtraArgs = "-p site-server -- --deny warnings";
          });
          site-frontend-clippy = craneLib.cargoClippy (common-args // {
            cargoArtifacts = site-server-deps;
            cargoClippyExtraArgs = "-p site-frontend -- --deny warnings";
          });

          # make sure the final binary builds
          # I used to build the container but I took it out so that the checks
          #   didn't need to have the surrealdb package, and I don't test it
          #   past just the binary anyways
          binary-builds = site-server;

          # # make sure the docs build
          # site-server-doc = craneLib.cargoDoc (common-args // {
          #   cargoArtifacts = site-server-deps;
          # });

          # check formatting
          site-server-fmt = craneLib.cargoFmt {
            inherit (common-args) pname version;
            inherit src;
          };
        };

        packages = {
          default = pkgs.callPackage ./nix/pkg.nix {};
          #default = site-server;
          #deps-only = site-server-deps;
          #server = site-server;
          #container = site-server-container;
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = (with pkgs; [
            toolchain # cargo and such from crane

            just # command recipes
            dive # docker images
            flyctl # fly.io
            bacon # cargo check w/ hot reload
            marksman # markdown lsp

            cargo-leptos # main leptos build tool
            # used by cargo-leptos for styling
            dart-sass
            tailwindcss
          ]) ++ common-args.buildInputs ++ common-args.nativeBuildInputs
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.Security ];
        };
      }) // {
        nixosModules = rec {
          esw-machines = inputs:
            import ./nix/esw-machines.nix (inputs // {
              esw-package = self.packages.x86_64-linux.default;
              inherit leptos-options;
            });
          default = esw-machines;
        };
        hydraJobs = flake-utils.lib.eachDefaultSystem (system:
          {packages = self.packages.${system}.default;}
        );
      };
}
