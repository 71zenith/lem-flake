{
  description = "Lem Editor";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      micros = pkgs.sbcl.buildASDFSystem {
        pname = "micros";
        version = "latest";
        src = pkgs.fetchFromGitHub {
          owner = "lem-project";
          repo = "micros";
          rev = "f80d7772ca76e9184d9bc96bc227147b429b11ed";
          hash = "sha256-RiBHxKWVZsB4JPktLSVcup7WIUMk08VbxU1zeBfGrFQ=";
        };
        patches = [./micros.patch];
      };
      jsonrpc = pkgs.sbclPackages.jsonrpc.overrideLispAttrs (oldAttrs: {
        systems = ["jsonrpc" "jsonrpc/transport/stdio" "jsonrpc/transport/tcp"];
        lispLibs = with pkgs.sbclPackages;
          oldAttrs.lispLibs ++ [cl_plus_ssl quri fast-io trivial-utf-8];
      });
      cl-charms =
        pkgs.sbclPackages.cl-charms.overrideLispAttrs
        (oldAttrs: {nativeLibs = [pkgs.ncurses];});
      queues = pkgs.sbclPackages.queues.overrideLispAttrs (oldAttrs: {
        systems = ["queues" "queues.priority-cqueue" "queues.priority-queue" "queues.simple-cqueue" "queues.simple-queue"];
        lispLibs = oldAttrs.lispLibs ++ (with pkgs.sbclPackages; [bordeaux-threads]);
      });
      lem-mailbox = pkgs.sbcl.buildASDFSystem {
        pname = "lem-mailbox";
        version = "latest";
        src = pkgs.fetchFromGitHub {
          owner = "lem-project";
          repo = "lem-mailbox";
          rev = "12d629541da440fadf771b0225a051ae65fa342a";
          hash = "sha256-hb6GSWA7vUuvSSPSmfZ80aBuvSVyg74qveoCPRP2CeI=";
        };
        lispLibs = with pkgs.sbclPackages; [bordeaux-threads bt-semaphore queues];
      };
      lem-base16-themes = pkgs.sbcl.buildASDFSystem {
        pname = "lem-base16-themes";
        version = "latest";
        src = pkgs.fetchFromGitHub {
          owner = "71zenith";
          repo = "lem-base16-themes";
          rev = "bcc052d4f9161cba5ece9896dc76f46adadae23f";
          hash = "sha256-qHSBM2FXA5PNmckbIJxQE6aTVUz3moyIC3dXvNRJaMY=";
        };
        lispLibs = [lem];
      };
      lem = pkgs.callPackage ./default.nix {inherit micros lem-mailbox jsonrpc cl-charms queues lem;};
      lem-exec = frontend:
        pkgs.sbcl.buildASDFSystem {
          inherit (lem) src;
          pname = "lem-exec";
          version = "latest";
          lispLibs =
            [lem lem-base16-themes jsonrpc cl-charms]
            ++ (with pkgs.sbcl.pkgs; [_3bmd _3bmd-ext-code-blocks lisp-preprocessor trivial-ws trivial-open-browser])
            ++ (
              if frontend == "sdl2"
              then (with pkgs.sbcl.pkgs; [sdl2 sdl2-ttf sdl2-image trivial-main-thread])
              else []
            );
          nativeLibs =
            if frontend == "sdl2"
            then with pkgs; [SDL2 SDL2_ttf SDL2_image]
            else [];
          nativeBuildInputs = with pkgs; [openssl makeWrapper];
          buildScript = pkgs.writeText "build-lem.lisp" ''
            (load (concatenate 'string (sb-ext:posix-getenv "asdfFasl") "/asdf.fasl"))
            ; Uncomment this line to load the :lem-tetris contrib system
            ;(asdf:load-system :lem-tetris)
            ${
              if frontend == "sdl2"
              then "(asdf:load-system :lem-sdl2)"
              else "(asdf:load-system :lem-ncurses)"
            }
            (sb-ext:save-lisp-and-die
              "lem"
              :executable t
              :purify t
              #+sb-core-compression :compression
              #+sb-core-compression t
              :toplevel #'lem:main)
          '';
          patches = [./fix-quickload.patch];
          installPhase = ''
            mkdir -p $out/bin
            cp -v lem $out/bin
            wrapProgram $out/bin/lem \
              --prefix LD_LIBRARY_PATH : $LD_LIBRARY_PATH \
          '';
          passthru = {
            withPackages = import ./wrapper.nix {
              inherit (pkgs) makeWrapper sbcl lib symlinkJoin;
              lem = lem-exec frontend;
            };
          };
        };
    in {
      packages = rec {
        inherit lem-exec lem lem-base16-themes;
        lem-sdl2 = lem-exec "sdl2";
        lem-ncurses = lem-exec "ncurses";
        default = lem-sdl2;
      };
    })
    // {
      overlays = rec {
        default = lem;
        lem = final: prev: {
          lem-sdl2 = self.packages."${final.system}".lem-sdl2;
          lem-ncurses = self.packages."${final.system}".lem-ncurses;
        };
      };
    };
}
