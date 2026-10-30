{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "steam-config-launch";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../crates
    ];
  };
  cargoLock.lockFile = ../Cargo.lock;
  cargoBuildFlags = [
    "-p"
    "steam-config-launch"
  ];
  cargoTestFlags = [
    "-p"
    "steam-config-launch"
  ];
  meta = {
    description = "Launch step that applies a Steam app's launch options and serves its files";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "steam-config-launch";
  };
}
