{
  description = "Private inputs for the checks, fetched from this lock by the root flake";

  inputs.home-manager = {
    url = "github:nix-community/home-manager/release-26.05";
    flake = false;
  };

  outputs = _: { };
}
