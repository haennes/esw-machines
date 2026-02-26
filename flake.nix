{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ...}@inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import inputs.rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        toml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
        name = toml.package.name;
        version = toml.package.version;
        pkg = pkgs.callPackage ./nix/pkg.nix {
          inherit
            name
            version
            inputs
            toml
            ;
        };
      in
      {
        nixosModules = rec {
          esw-machines = import ./nix/esw-machines.nix self system;
          default = esw-machines;
        };
        inherit (pkg) packages;
        hydraJobs.packages = self.packages.${system}.default;
      }
    );
}
