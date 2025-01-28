{
  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:

    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShell = pkgs.mkShell {
          buildInputs =
            with pkgs;
            [
              zig
              zls
            ]
            ++ lib.optional stdenv.isDarwin [
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.CoreServices
              darwin.apple_sdk.frameworks.CoreFoundation
              darwin.apple_sdk.frameworks.Foundation
              darwin.apple_sdk.frameworks.AppKit
              darwin.apple_sdk.frameworks.WebKit
              darwin.apple_sdk.frameworks.Cocoa
            ];
        };
      }
    );

}
