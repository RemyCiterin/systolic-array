{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    # RTL simulation
    pkgs.bluespec
    pkgs.verilator
    pkgs.verilog
    pkgs.gtkwave

    # Some tools for FPGA implementation
    pkgs.yosys
    pkgs.nextpnr
    pkgs.trellis
    pkgs.icestorm
    pkgs.python313Packages.apycula
    pkgs.openfpgaloader

    # View dot files
    pkgs.xdot
  ];

  shellHook = ''
    export BLUESPECDIR=${pkgs.bluespec}/lib
    '';
}
