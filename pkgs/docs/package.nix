self:
{
  lib,
  pkgs,
  stdenv,
  hugo,
  mkSearch,
  nixosOptionsDoc,
  fetchurl,
  ...
}:
let
  siteUrl = "https://different-name.github.io/steam-config-nix/";
  # cut out of the one url rather than spelling the prefix out in a second place
  basePath =
    "/"
    + lib.concatStringsSep "/" (
      lib.drop 1 (
        lib.filter (s: s != "") (lib.splitString "/" (lib.last (lib.splitString "://" siteUrl)))
      )
    );

  # the search page and the docs option check read the same tree, so evaluate it once
  optionsJson =
    let
      eval = lib.evalModules {
        specialArgs = { inherit pkgs; };
        modules = [
          { config._module.check = false; }
          self.homeModules.default
        ];
      };
    in
    (nixosOptionsDoc { inherit (eval) options; }).optionsJSON + "/share/doc/nixos/options.json";

  search = mkSearch {
    optionsJSON = optionsJson;
    urlPrefix = "https://github.com/different-name/steam-config-nix/blob/main/";
    baseHref = "${basePath}/search/";
    title = "steam-config-nix options";
    hashLocation = true;
  };

  # hextra pulls this from a cdn at build time, which a sandboxed build cannot do
  flexsearch = fetchurl {
    url = "https://cdn.jsdelivr.net/npm/flexsearch@0.8.143/dist/flexsearch.bundle.min.js";
    hash = "sha256-Qz6UGopXPruZMfwW/HUmara5P1aawvtPPcZoguBBb0w=";
  };
in
stdenv.mkDerivation {
  name = "steam-config-nix-docs";
  src = ../../docs;

  nativeBuildInputs = [ hugo ];

  buildPhase = ''
    runHook preBuild

    mkdir -p themes
    ln -s ${self.inputs.hextra} themes/hextra
    install -Dm644 ${flexsearch} assets/js/flexsearch.bundle.min.js

    # hextra does not resolve @import in custom.css
    cat assets/css/catppuccin.css assets/css/site.css > assets/css/custom.css

    HUGO_CACHEDIR="$TMPDIR/hugo-cache" hugo \
      --baseURL "${siteUrl}" \
      --destination "$out" \
      --logLevel warn

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    cp -r ${search} $out/search
    chmod -R u+w $out/search

    # the search app has no theming or navigation hooks, so both are injected into its page
    # hashed like the app's own stylesheets, or a cached copy hides the change
    css="steam-config-nix.$(sha256sum ${./search.css} | cut -c1-16).css"
    install -Dm644 ${./search.css} "$out/search/$css"
    substituteInPlace $out/search/index.html \
      --replace-fail '</head>' \
        "<link rel=\"stylesheet\" href=\"$css\"></head>" \
      --replace-fail '<app-root>' \
        '<a class="scn-back" href="${basePath}/docs/">Guide</a><app-root>'

    runHook postInstall
  '';

  passthru = { inherit basePath optionsJson; };
}
