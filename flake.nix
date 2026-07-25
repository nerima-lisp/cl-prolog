{
  description = "Dependency-free Common Lisp Prolog engine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # cl-weave is the testing library used by the cl-prolog/tests ASDF system.
  # suite.  It follows this flake's nixpkgs so both share a single SBCL.
  inputs.cl-weave.url = "github:nerima-lisp/cl-weave/v0.4.0";
  inputs.cl-weave.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-weave.inputs.paredit-cli.follows = "paredit-cli";

  # paredit-cli provides structural S-expression tooling for this repo's
  # Lisp sources: a dev-shell binary for agent-driven refactors and a
  # structural-parse lint gate reused in `checks`.
  inputs.paredit-cli.url = "github:nerima-lisp/paredit-cli";
  inputs.paredit-cli.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self
    , nixpkgs
    , cl-weave
    , paredit-cli
    ,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        builtins.listToAttrs (
          map
            (system: {
              name = system;
              value = f system;
            })
            systems
        );
      # Single source of truth for the project version: parse `:version`
      # straight out of cl-prolog.asd so the flake can never drift from the
      # ASDF system definition (previously the package pinned a stale 0.6.0).
      projectVersion =
        let
          asd = builtins.readFile ./cl-prolog.asd;
          # Match only lines that are literally `:version "X"`, so a comment
          # or docstring merely mentioning :version can never shadow the real
          # definition. An empty result asserts loudly instead of failing with
          # an opaque `builtins.head` error on the malformed source.
          matches = builtins.filter (m: m != null) (
            map (builtins.match ''[[:space:]]*:version[[:space:]]+"([^"]+)".*'') (
              nixpkgs.lib.splitString "\n" asd
            )
          );
        in
        assert matches != [ ];
        builtins.head (builtins.head matches);
      # Shared CL_SOURCE_REGISTRY export so the dev shell and the `test` app
      # agree on how cl-weave and the working tree land on ASDF's search path.
      clSourceRegistryExport =
        clWeavePackage:
        ''export CL_SOURCE_REGISTRY="${clWeavePackage}/share/common-lisp/source//:$PWD//:''${CL_SOURCE_REGISTRY:-}"'';
      sourceFor =
        pkgs:
        pkgs.lib.cleanSourceWith {
          src = ./.;
          filter =
            path: type:
            (
              (pkgs.lib.cleanSourceFilter path type)
              # Retain test sources present in the Git-backed flake input.
              # This filter cannot reintroduce files excluded as untracked.
              || (
                let
                  tests-directory = "${toString ./.}/tests";
                  path-string = toString path;
                in
                path-string == tests-directory || pkgs.lib.hasPrefix "${tests-directory}/" path-string
              )
            )
            && (
              let
                name = builtins.baseNameOf path;
              in
                !(
                  pkgs.lib.hasSuffix ".fasl" name
                  || pkgs.lib.hasSuffix ".cfasl" name
                  || pkgs.lib.hasSuffix ".dfsl" name
                  || pkgs.lib.hasSuffix ".ufasl" name
                  || pkgs.lib.hasSuffix ".core" name
                  || pkgs.lib.hasSuffix ".o" name
                )
            );
        };
      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-prolog-docs";
          version = projectVersion;
          src = pkgs.lib.fileset.toSource {
            root = ./docs;
            fileset = pkgs.lib.fileset.unions [
              ./docs/mkdocs.yml
              ./docs/src
            ];
          };
          nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          buildPhase = ''
            runHook preBuild
            mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered MkDocs (Material) documentation for cl-prolog";
            homepage = "https://github.com/takeokunn/cl-prolog";
            license = pkgs.lib.licenses.mit;
          };
        };
    in
    {
      formatter = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixpkgs-fmt
      );

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          src = sourceFor pkgs;
          cl-prolog = pkgs.sbcl.buildASDFSystem {
            pname = "cl-prolog";
            version = projectVersion;
            src = src;
            systems = [ "cl-prolog" ];
          };
        in
        {
          inherit cl-prolog;
          default = cl-prolog;
          docs = mkDocs pkgs;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          src = sourceFor pkgs;
          # Shared sandbox prelude for the SBCL-driven checks: copy the clean
          # source into a writable tree and keep HOME/XDG under the build's
          # TMPDIR so SBCL and ASDF never touch the real user profile.
          sbclCheckPrelude = ''
            cp -R ${src} source
            chmod -R u+w source
            cd source
            export HOME="$TMPDIR/home"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            mkdir -p "$HOME" "$XDG_CACHE_HOME"
          '';
          # Build an SBCL check from the shared prelude, an optional extra
          # environment block, and the ASDF form to evaluate.  Centralising
          # this keeps `default` and `examples` from drifting apart.
          mkSbclCheck =
            { name
            , extraEnv ? ""
            , operation
            ,
            }:
            pkgs.runCommand name { nativeBuildInputs = [ pkgs.sbcl ]; } ''
              ${sbclCheckPrelude}${extraEnv}
              timeout 600 sbcl --non-interactive \
                --eval '(require :asdf)' \
                --eval '(asdf:load-asd (truename "cl-prolog.asd"))' \
                --eval '${operation}'
              touch $out
            '';
        in
        {
          # The complete suite is an ASDF system.  cl-weave is exposed through
          # CL_SOURCE_REGISTRY, so no project-local test runner is required.
          default = mkSbclCheck {
            name = "cl-prolog-weave-tests";
            extraEnv = ''
              export CL_SOURCE_REGISTRY="${cl-weave.packages.${system}.default}/share/common-lisp/source//:$PWD//:"
            '';
            operation = "(asdf:test-system :cl-prolog/tests)";
          };

          # Structural parse gate over every tracked Lisp source: fails if
          # any .lisp/.asd file is not a balanced S-expression document.
          paredit-lint = paredit-cli.lib.${system}.mkLintCheck {
            src = src;
            name = "cl-prolog-paredit-lint";
          };

          # Ensure every shipped example loads from the same clean source used
          # by the package and CI checks.
          examples = mkSbclCheck {
            name = "cl-prolog-examples";
            operation = "(asdf:load-system :cl-prolog/examples)";
          };

          # Fails if the MkDocs site does not build to a valid index.html.
          documentation =
            pkgs.runCommand "cl-prolog-documentation" { docs = self.packages.${system}.docs; }
              ''
                test -f "$docs/index.html"
                touch $out
              '';

          # Keep the flake aligned with the formatter exposed by this flake.
          formatting =
            pkgs.runCommand "cl-prolog-nix-formatting"
              {
                nativeBuildInputs = [ pkgs.nixpkgs-fmt ];
              }
              ''
                nixpkgs-fmt --check ${./flake.nix}
                touch $out
              '';
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          clWeavePackage = cl-weave.packages.${system}.default;
          test = pkgs.writeShellApplication {
            name = "cl-prolog-test";
            runtimeInputs = [ clWeavePackage ];
            text = ''
              ${clSourceRegistryExport clWeavePackage}
              exec cl-weave run cl-prolog/tests "$@"
            '';
          };
        in
        {
          test = {
            type = "app";
            program = "${test}/bin/cl-prolog-test";
            meta.description = "Run the cl-prolog cl-weave ASDF test suite";
          };
          default = self.apps.${system}.test;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          clWeavePackage = cl-weave.packages.${system}.default;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixpkgs-fmt
              pkgs.sbcl
              pkgs.python3Packages.mkdocs-material
              self.packages.${system}.default
              clWeavePackage
              paredit-cli.packages.${system}.default
            ];
            shellHook = ''
              ${clSourceRegistryExport clWeavePackage}
            '';
          };
        }
      );
    };
}
