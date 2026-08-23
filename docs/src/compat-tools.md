# Compatibility Tools

`compatTool` and `defaultCompatTool` accept either the internal name of a compatibility tool that is already installed, or a package containing one:

```nix
{
  programs.steam.config = {
    defaultCompatTool = "proton_experimental";

    apps."1091500" = {
      name = "Cyberpunk 2077";
      compatTool = pkgs.proton-ge-bin;
    };
  };
}
```

Tools provided as packages are installed for you:

- NixOS: through `programs.steam.extraCompatPackages`, requires `programs.steam.enable`
- Home Manager: linked into `~/.local/share/Steam/compatibilitytools.d`

Versions that are not packaged in nixpkgs can be fetched directly from their releases. Any archive containing a `compatibilitytool.vdf` at its root will work:

```nix
{
  compatTool = pkgs.fetchzip {
    url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-10/GE-Proton10-10.tar.gz";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
}
```
