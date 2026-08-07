self:
{
  lib,
  pkgs,
  stdenv,
  nixosOptionsDoc,
  mdbook,
  fetchurl,
  ...
}:
let
  eval = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      { config._module.check = false; }
      self.homeModules.default
    ];
  };

  mkOptionsDoc = options: nixosOptionsDoc { inherit options; };

  globalOptionsDoc = mkOptionsDoc (
    removeAttrs eval.options.programs.steam.config [
      "apps"
      "nonSteamApps"
    ]
  );
  appOptionsDoc = mkOptionsDoc { inherit (eval.options.programs.steam.config) apps; };
  nonSteamAppOptionsDoc = mkOptionsDoc { inherit (eval.options.programs.steam.config) nonSteamApps; };

  catppuccinCss = fetchurl {
    url = "https://github.com/catppuccin/mdBook/releases/download/v4.0.0/catppuccin.css";
    hash = "sha256-4IvmqQrfOSKcx6PAhGD5G7I44UN2596HECCFzzr/p/8=";
  };
in
stdenv.mkDerivation {
  name = "steam-config-nix-docs";
  src = ../../docs;

  nativeBuildInputs = [ mdbook ];

  buildPhase = ''
    runHook preBuild

    cat ${globalOptionsDoc.optionsCommonMark} >> src/options-global.md
    cat ${appOptionsDoc.optionsCommonMark} >> src/options-apps.md
    cat ${nonSteamAppOptionsDoc.optionsCommonMark} >> src/options-non-steam-apps.md
    install -Dm644 ${catppuccinCss} theme/catppuccin.css

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mdbook build -d $out

    runHook postInstall
  '';
}
