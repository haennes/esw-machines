{ rustPlatform, lib, pkgs, ...}:
rustPlatform.buildRustPackage rec{
  name = "esw-machines";
  pname = name;
  version = "1.0";
  src = ../.;
  nativeBuildInputs = with pkgs; [
  cargo-leptos
  lld
  binaryen
  dart-sass
  makeWrapper
  ];
  cargoHash = "sha256-Y7qLDLz+rk+42p44wqDKg2T0AYXLE3ZjAEVmblhGePI=";
  useFetchCargoVendor = true;
  buildPhase = ''
  cargo leptos build --release -vvv
  '';
  installPhase = ''
  mkdir -p $out/bin
  cp target/release/${name} $out/bin/
  cp -r target/site $out/bin/
  wrapProgram $out/bin/${name} \
    --set LEPTOS_SITE_ROOT $out/bin/site
  '';
}
