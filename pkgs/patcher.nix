{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "steam-config-patcher";
  version = (lib.importTOML ../Cargo.toml).workspace.package.version;
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
    homepage = "https://github.com/different-name/steam-config-nix";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "steam-config-patcher";
  };
}
