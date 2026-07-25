{
  description = "Dependency-free Common Lisp Prolog engine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # cl-weave is the testing library used by the cl-prolog/test ASDF system. It
  # follows this flake's nixpkgs so both share a single SBCL.
  inputs.cl-weave.url = "github:nerima-lisp/cl-weave/v1.0.0";
  inputs.cl-weave.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-weave.inputs.paredit-cli.follows = "paredit-cli";

  # paredit-cli provides structural S-expression tooling for this repo's
  # Lisp sources: a dev-shell binary for agent-driven refactors and a
  # structural-parse lint gate reused in `checks`.
  inputs.paredit-cli.url = "github:nerima-lisp/paredit-cli/v0.8.0";
  inputs.paredit-cli.inputs.nixpkgs.follows = "nixpkgs";

  # treefmt drives `nix fmt` and the checks.formatting gate. Scope is Nix only:
  # nixfmt is a low-diff, zero-configuration formatter, whereas a YAML
  # formatter mangles the GitHub Actions `on:` key and reformatting Markdown
  # would churn all 24 docs pages for no reviewable gain.
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      self,
      nixpkgs,
      cl-weave,
      paredit-cli,
      treefmt-nix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
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
                  test-directory = "${toString ./.}/t";
                  path-string = toString path;
                in
                path-string == test-directory || pkgs.lib.hasPrefix "${test-directory}/" path-string
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
            homepage = "https://github.com/nerima-lisp/cl-prolog";
            license = pkgs.lib.licenses.mit;
          };
        };
    in
    {
      # `nix fmt` entry point, and the same derivation checks.formatting runs.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

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
        in
        {
          # Runs run-tests.lisp, the same file a developer runs by hand, rather
          # than re-spelling the ASDF invocation here: the local command and the
          # CI gate cannot then drift apart. cl-weave is exposed through
          # CL_SOURCE_REGISTRY.
          #
          # -k sends SIGKILL 30s after the SIGTERM deadline: SBCL defers signals
          # to safepoints, so a tight compiled loop (a runaway Prolog
          # backtracking bug is exactly this) can outlive a bare SIGTERM and
          # fall through to the enclosing CI job timeout instead of failing here
          # with an attributable error.
          default = pkgs.runCommand "cl-prolog-weave-tests" { nativeBuildInputs = [ pkgs.sbcl ]; } ''
            ${sbclCheckPrelude}
            export CL_SOURCE_REGISTRY="${
              cl-weave.packages.${system}.default
            }/share/common-lisp/source//:$PWD//:"
            timeout -k 30 600 sbcl --script run-tests.lisp
            touch $out
          '';

          # Structural parse gate over every tracked Lisp source: fails if
          # any .lisp/.asd file is not a balanced S-expression document.
          paredit-lint = paredit-cli.lib.${system}.mkLintCheck {
            src = src;
            name = "cl-prolog-paredit-lint";
          };

          # Ensure every shipped example loads from the same clean source used
          # by the package and CI checks. A plain load-system has no
          # backtracking search to run away, so it gets a much smaller budget
          # than the full suite above.
          examples = pkgs.runCommand "cl-prolog-examples" { nativeBuildInputs = [ pkgs.sbcl ]; } ''
            ${sbclCheckPrelude}
            timeout -k 30 120 sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:load-asd (truename "cl-prolog.asd"))' \
              --eval '(asdf:load-system :cl-prolog/examples)'
            touch $out
          '';

          # packages.docs runs `mkdocs build --strict`, so a broken link or a
          # page missing from the nav fails here rather than after a merge, in
          # the Pages deploy. The index.html assertion additionally catches a
          # --strict build that succeeded while producing nothing.
          docs = pkgs.runCommand "cl-prolog-documentation" { docs = self.packages.${system}.docs; } ''
            test -f "$docs/index.html"
            touch $out
          '';

          # Fails `nix flake check` when any tracked Nix file is unformatted,
          # which is what makes `nix fmt` an enforced gate rather than a
          # suggestion. Checks the whole tree, not just flake.nix as before.
          formatting = treefmtEval.${system}.config.build.check self;

          # `nix flake check` only evaluates `packages` and `apps`, it does
          # not realise their derivations. README.md's headline command,
          # `nix run github:nerima-lisp/cl-prolog`, resolves through
          # packages.default -> apps.default -> the cl-weave-backed wrapper
          # below; without this, neither ever actually gets built in CI.
          # Mirrors the `package = self.packages.${system}.default;` check
          # convention already used by paredit-cli's own flake.
          package = self.packages.${system}.default;

          # `checks.default` above runs the suite through run-tests.lisp under
          # a plain SBCL with the compiled-in default dynamic space. The
          # `apps.test` wrapper below runs the SAME suite through cl-weave's
          # own CLI, which sets a 4096 MB dynamic space — a genuinely
          # different code path that was previously never exercised by `nix
          # flake check`, so a heap-pressure-sensitive test could pass one
          # way and fail the other with no CI signal either way.
          app-test = pkgs.runCommand "cl-prolog-app-test" { nativeBuildInputs = [ pkgs.sbcl ]; } ''
            ${sbclCheckPrelude}
            timeout -k 30 600 ${self.apps.${system}.test.program}
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
              exec cl-weave run cl-prolog/test "$@"
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
              # Same wrapper `nix fmt` and checks.formatting use, so formatting
              # inside the shell cannot disagree with the gate.
              treefmtEval.${system}.config.build.wrapper
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
