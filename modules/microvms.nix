{
  config,
  extraLib,
  inputs,
  lib,
  microvm,
  nodeName,
  nodePath,
  pkgs,
  utils,
  ...
}: let
  inherit
    (lib)
    any
    attrNames
    attrValues
    concatStringsSep
    escapeShellArg
    filterAttrs
    foldl'
    makeBinPath
    mapAttrsToList
    mdDoc
    mkDefault
    mkEnableOption
    mkForce
    mkIf
    mkMerge
    mkOption
    optional
    optionalAttrs
    recursiveUpdate
    types
    ;

  parentConfig = config;
  cfg = config.extra.microvms;
  inherit (config.extra.microvms) vms;
  inherit (config.lib) net;

  # Configuration for each microvm
  microvmConfig = vmName: vmCfg: {
    # Add the required datasets to the disko configuration of the machine
    disko.devices.zpool = mkIf vmCfg.zfs.enable {
      ${vmCfg.zfs.pool}.datasets."${vmCfg.zfs.dataset}" =
        extraLib.disko.zfs.filesystem vmCfg.zfs.mountpoint;
    };

    # Ensure that the zfs dataset exists before it is mounted.
    systemd.services = let
      fsMountUnit = "${utils.escapeSystemdPath vmCfg.zfs.mountpoint}.mount";
    in
      mkIf vmCfg.zfs.enable {
        # Ensure that the zfs dataset exists before it is mounted.
        "zfs-ensure-${utils.escapeSystemdPath vmCfg.zfs.mountpoint}" = {
          wantedBy = [fsMountUnit];
          before = [fsMountUnit];
          after = [
            "zfs-import-${utils.escapeSystemdPath vmCfg.zfs.pool}.service"
            "zfs-mount.target"
          ];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = let
            poolDataset = "${vmCfg.zfs.pool}/${vmCfg.zfs.dataset}";
            diskoDataset = config.disko.devices.zpool.${vmCfg.zfs.pool}.datasets.${vmCfg.zfs.dataset};
          in ''
            export PATH=${makeBinPath [pkgs.zfs]}":$PATH"
            if ! zfs list -H -o type ${escapeShellArg poolDataset} &>/dev/null ; then
              ${diskoDataset._create {zpool = vmCfg.zfs.pool;}}
            fi
          '';
        };

        # Ensure that the zfs dataset has the correct permissions when mounted
        "zfs-chown-${utils.escapeSystemdPath vmCfg.zfs.mountpoint}" = {
          after = [fsMountUnit];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            chmod 700 ${escapeShellArg vmCfg.zfs.mountpoint}
          '';
        };

        "microvm@${vmName}" = {
          requires = [fsMountUnit "zfs-chown-${utils.escapeSystemdPath vmCfg.zfs.mountpoint}.service"];
          after = [fsMountUnit "zfs-chown-${utils.escapeSystemdPath vmCfg.zfs.mountpoint}.service"];
        };
      };

    # Propagate node expansions, since doing this directly in the
    # distributed-config module would cause infinite recursion.
    nodes = mkMerge config.microvm.vms.${vmName}.config.options.nodes.definitions;

    microvm.vms.${vmName} = let
      node = import ../nix/generate-node.nix inputs vmCfg.nodeName {
        inherit (vmCfg) system configPath;
      };
      mac = (net.mac.assignMacs "02:01:27:00:00:00" 24 [] (attrNames vms)).${vmName};
    in {
      # Allow children microvms to know which node is their parent
      specialArgs =
        {
          parentNode = config;
          parentNodeName = nodeName;
        }
        // node.specialArgs;
      inherit (node) pkgs;
      inherit (vmCfg) autostart;
      config = {config, ...}: {
        imports = cfg.commonImports ++ node.imports;

        microvm = {
          hypervisor = mkDefault "cloud-hypervisor";

          # MACVTAP bridge to the host's network
          interfaces = [
            {
              type = "macvtap";
              id = "vm-${vmName}";
              inherit mac;
              macvtap = {
                link = cfg.networking.macvtapInterface;
                mode = "bridge";
              };
            }
          ];

          shares =
            [
              # Share the nix-store of the host
              {
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                tag = "ro-store";
                proto = "virtiofs";
              }
              {
                source = "/state/vms/${vmName}";
                mountPoint = "/state";
                tag = "state";
                proto = "virtiofs";
              }
            ]
            # Mount persistent data from the host
            ++ optional vmCfg.zfs.enable {
              source = vmCfg.zfs.mountpoint;
              mountPoint = "/persist";
              tag = "persist";
              proto = "virtiofs";
            };
        };

        # FIXME this should be changed in microvm.nix to mkDefault in oder to not require mkForce here
        fileSystems."/state".neededForBoot = mkForce true;
        fileSystems."/persist".neededForBoot = mkForce true;

        # Add a writable store overlay, but since this is always ephemeral
        # disable any store optimization from nix.
        microvm.writableStoreOverlay = "/nix/.rw-store";
        nix = {
          settings.auto-optimise-store = mkForce false;
          optimise.automatic = mkForce false;
          gc.automatic = mkForce false;
        };

        extra.networking.renameInterfacesByMac.${vmCfg.networking.mainLinkName} = mac;

        systemd.network.networks =
          {
            "10-${vmCfg.networking.mainLinkName}" = {
              matchConfig.MACAddress = mac;
              DHCP = "yes";
              networkConfig = {
                IPv6PrivacyExtensions = "yes";
                MulticastDNS = true;
                IPv6AcceptRA = true;
              };
              linkConfig.RequiredForOnline = "routable";
            };
          }
          // optionalAttrs vmCfg.localWireguard {
            # Remove requirement for the wireguard interface to come online,
            # to allow microvms to be deployed more easily (otherwise they
            # would not come online if the private key wasn't rekeyed yet).
            # FIXME ideally this would be conditional at runtime if the
            # agenix activation had an error, but this is not trivial.
            ${parentConfig.extra.wireguard."${nodeName}-local-vms".unitConfName} = {
              linkConfig.RequiredForOnline = "no";
            };
          };

        # TODO mkForce nftables
        networking.nftables.firewall = {
          zones = mkForce {
            untrusted.interfaces = [vmCfg.networking.mainLinkName];
          };
        };

        extra.wireguard = mkIf vmCfg.localWireguard {
          "${nodeName}-local-vms" = {
            server = {
              host =
                if config.networking.domain == null
                then "${config.networking.hostName}.local"
                else config.networking.fqdn;
              inherit (cfg.networking.wireguard) port;
              openFirewallRules = ["untrusted-to-local"];
            };
            linkName = "local-vms";
          };
        };
      };
    };
  };
in {
  imports = [
    # Add the host module, but only enable if it necessary
    microvm.host
    # This is opt-out, so we can't put this into the mkIf below
    {microvm.host.enable = vms != {};}
  ];

  options.extra.microvms = {
    commonImports = mkOption {
      type = types.listOf types.unspecified;
      default = [];
      description = mdDoc "Modules to import on all microvms.";
    };

    networking = {
      baseMac = mkOption {
        type = net.types.mac;
        description = mdDoc ''
          This MAC address will be used as a base address to derive all MicroVM MAC addresses from.
          A good practise is to use the physical address of the macvtap interface.
        '';
      };

      macvtapInterface = mkOption {
        type = types.str;
        description = mdDoc "The macvtap interface to which MicroVMs should be attached";
      };

      wireguard = {
        cidrv4 = mkOption {
          type = net.types.cidrv4;
          description = mdDoc "The ipv4 network address range to use for internal vm traffic.";
          default = "172.31.0.0/24";
        };

        cidrv6 = mkOption {
          type = net.types.cidrv6;
          description = mdDoc "The ipv6 network address range to use for internal vm traffic.";
          default = "fd00:172:31::/120";
        };

        port = mkOption {
          default = 51829;
          type = types.port;
          description = mdDoc "The port to listen on.";
        };

        openFirewallRules = mkOption {
          default = [];
          type = types.listOf types.str;
          description = mdDoc "The {option}`port` will be opened for all of the given rules in the nftable-firewall.";
        };
      };
    };

    vms = mkOption {
      default = {};
      description = "Defines the actual vms and handles the necessary base setup for them.";
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: {
        options = {
          nodeName = mkOption {
            type = types.str;
            default = "${nodeName}-${name}";
            description = mdDoc ''
              The name of the resulting node. By default this will be a compound name
              of the host's name and the vm's name to avoid name clashes. Can be
              overwritten to designate special names to specific vms.
            '';
          };

          configPath = mkOption {
            type = types.nullOr types.path;
            default =
              if nodePath != null && builtins.pathExists (nodePath + "/microvms/${name}")
              then nodePath + "/microvms/${name}"
              else null;
            description = mdDoc ''
              The main configuration directory for this microvm. If not-null, the given
              directory will automatically be imported as system configuration. It will
              become the nodePath for the microvm meaning that some machine-specific files
              may be referenced there automatically (for example host.pub).

              This can also be set to a file, which will then simply be used as the main
              import for configuration, without setting a nodePath.

              By default this will be set to the current node's <nodePath>/microvms/<vmname>
              if the current nodePath is non-null and the directory exists.
            '';
          };

          networking = {
            mainLinkName = mkOption {
              type = types.str;
              default = "wan";
              description = mdDoc "The main ethernet link name inside of the VM";
            };
          };

          zfs = {
            enable = mkEnableOption (mdDoc "Enable persistent data on separate zfs dataset");

            pool = mkOption {
              type = types.str;
              description = mdDoc "The host's zfs pool on which the dataset resides";
            };

            dataset = mkOption {
              type = types.str;
              default = "safe/vms/${name}";
              description = mdDoc "The host's dataset that should be used for this vm's state (will automatically be created, parent dataset must exist)";
            };

            mountpoint = mkOption {
              type = types.str;
              default = "/vms/${name}";
              description = mdDoc "The host's mountpoint for the vm's dataset (will be shared via virtiofs as /persist in the vm)";
            };
          };

          autostart = mkOption {
            type = types.bool;
            default = false;
            description = mdDoc "Whether this VM should be started automatically with the host";
          };

          localWireguard = mkOption {
            type = types.bool;
            default = false;
            description = mdDoc "Whether this VM should be connected to a local wireguard network with other VMs (that opt-in here) on the same host.";
          };

          system = mkOption {
            type = types.str;
            description = mdDoc "The system that this microvm should use";
          };
        };
      }));
    };
  };

  config = mkIf (vms != {}) (
    {
      # Define a local wireguard server to communicate with vms securely
      extra.wireguard = mkIf (any (x: x.localWireguard) (attrValues vms)) {
        "${nodeName}-local-vms" = {
          server = {
            host =
              if config.networking.domain == null
              then "${config.networking.hostName}.local"
              else config.networking.fqdn;
            inherit (cfg.networking.wireguard) openFirewallRules port;
            reservedAddresses = [cfg.networking.wireguard.cidrv4 cfg.networking.wireguard.cidrv6];
          };
          linkName = "local-vms";
          ipv4 = net.cidr.host 1 cfg.networking.wireguard.cidrv4;
          ipv6 = net.cidr.host 1 cfg.networking.wireguard.cidrv6;
        };
      };
    }
    // extraLib.mergeToplevelConfigs ["nodes" "disko" "microvm" "systemd"] (mapAttrsToList microvmConfig vms)
  );
}
