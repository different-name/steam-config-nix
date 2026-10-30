{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "steam-config-patcher";
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
    "steam-config-patcher"
  ];
  cargoTestFlags = [
    "-p"
    "steam-config-vdf"
    "-p"
    "steam-config-patcher"
  ];
  meta = {
    description = "Writes the declared configuration into Steam's files while Steam is closed";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "steam-config-patcher";
  };
}
