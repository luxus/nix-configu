{
  config,
  extraLib,
  inputs,
  lib,
  microvm,
  nodeName,
  nodePath,
  pkgs,
  ...
}: let
  inherit
    (lib)
    attrNames
    concatStringsSep
    filterAttrs
    mapAttrs
    mapAttrsToList
    mdDoc
    mkDefault
    mkForce
    mkIf
    mkOption
    types
    ;

  cfg = config.extra.microvms;

  defineMicrovm = vmName: vmCfg: let
    node =
      (import ../nix/generate-node.nix inputs)
      "${nodeName}-microvm-${vmName}" {
        inherit (vmCfg) system;
        config = nodePath + "/microvms/${vmName}";
      };
  in {
    inherit (node) pkgs specialArgs;
    config = {
      imports = [microvm.microvm] ++ node.imports;

      microvm = {
        hypervisor = mkDefault "cloud-hypervisor";

        # MACVTAP bridge to the host's network
        interfaces = [
          {
            type = "macvtap";
            id = "vm-${vmName}";
            macvtap = {
              link = vmCfg.macvtap;
              mode = "bridge";
            };
            inherit (vmCfg) mac;
          }
        ];

        shares = [
          # Share the nix-store of the host
          {
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }
          # Mount persistent data from the host
          #{
          #  source = "/persist/vms/${vmName}";
          #  mountPoint = "/persist";
          #  tag = "persist";
          #  proto = "virtiofs";
          #}
        ];
      };

      # TODO change once microvms are compatible with stage-1 systemd
      boot.initrd.systemd.enable = mkForce false;
    };
  };
in {
  imports = [microvm.host];

  options.extra.microvms = mkOption {
    default = {};
    description = "Provides a base configuration for MicroVMs.";
    type = types.attrsOf (types.submodule {
      options = {
        autostart = mkOption {
          type = types.bool;
          default = false;
          description = mdDoc "Whether this VM should be started automatically with the host";
        };

        mac = mkOption {
          type = config.lib.net.types.mac;
          description = mdDoc "The MAC address to assign to this VM";
        };

        macvtap = mkOption {
          type = types.str;
          description = mdDoc "The macvtap interface to attach to";
        };

        system = mkOption {
          type = types.str;
          description = mdDoc "The system that this microvm should use";
        };
      };
    });
  };

  config = {
    assertions = let
      duplicateMacs = extraLib.duplicates (mapAttrsToList (_: vmCfg: vmCfg.mac) cfg);
    in [
      {
        assertion = duplicateMacs == [];
        message = "Duplicate MicroVM MAC addresses: ${concatStringsSep ", " duplicateMacs}";
      }
    ];

    microvm = {
      host.enable = cfg != {};
      declarativeUpdates = true;
      restartIfChanged = true;
      vms = mkIf (cfg != {}) (mapAttrs defineMicrovm cfg);
      autostart = mkIf (cfg != {}) (attrNames (filterAttrs (_: v: v.autostart) cfg));
    };
  };
}
