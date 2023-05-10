{
  config,
  lib,
  nodeSecrets,
  ...
}: let
  inherit (config.lib.net) cidr;

  net.lan.ipv4cidr = "192.168.100.1/24";
  net.lan.ipv6cidr = "fd01::1/64";
in {
  networking.hostId = nodeSecrets.networking.hostId;

  boot.initrd.systemd.network = {
    enable = true;
    networks."10-wan" = {
      DHCP = "yes";
      #address = [
      #  "192.168.178.2/24"
      #  "fd00::1/64"
      #];
      #gateway = [
      #];
      matchConfig.MACAddress = nodeSecrets.networking.interfaces."wan-nic".mac;
      networkConfig.IPv6PrivacyExtensions = "kernel";
      dhcpV4Config.RouteMetric = 20;
      dhcpV6Config.RouteMetric = 20;
    };
  };

  systemd.network.netdevs."10-wan" = {
    netdevConfig = {
      Name = "wan";
      Kind = "macvtap";
    };
    extraConfig = ''
      [MACVTAP]
      Mode=bridge
    '';
  };

  systemd.network.networks = {
    "10-lan" = {
      address = [net.lan.ipv4cidr net.lan.ipv6cidr];
      matchConfig.MACAddress = nodeSecrets.networking.interfaces.lan.mac;
      networkConfig = {
        IPForward = "yes";
        IPv6PrivacyExtensions = "kernel";
      };
      dhcpV4Config.RouteMetric = 10;
      dhcpV6Config.RouteMetric = 10;
    };
    "10-wan-nic" = {
      matchConfig.MACAddress = nodeSecrets.networking.interfaces."wan-nic".mac;
      extraConfig = ''
        [Network]
        MACVTAP=wan
      '';
    };
    "11-wan" = {
      DHCP = "yes";
      #address = [
      #  "192.168.178.2/24"
      #  "fd00::1/64"
      #];
      #gateway = [
      #];
      matchConfig.Name = "wan";
      networkConfig.IPv6PrivacyExtensions = "kernel";
      dhcpV4Config.RouteMetric = 20;
      dhcpV6Config.RouteMetric = 20;
    };
  };

  networking.nftables.firewall = {
    zones = lib.mkForce {
      lan.interfaces = ["lan"];
      wan.interfaces = ["wan"];
    };

    rules = lib.mkForce {
      masquerade-wan = {
        from = ["lan"];
        to = ["wan"];
        masquerade = true;
      };

      outbound = {
        from = ["lan"];
        to = ["lan" "wan"];
        late = true; # Only accept after any rejects have been processed
        verdict = "accept";
      };

      wan-to-local = {
        from = ["wan"];
        to = ["local"];
      };

      lan-to-local = {
        from = ["lan"];
        to = ["local"];

        inherit
          (config.networking.firewall)
          allowedTCPPorts
          allowedUDPPorts
          ;
      };
    };
  };

  services.kea = {
    dhcp4 = {
      enable = true;
      settings = {
        lease-database = {
          name = "/var/lib/kea/dhcp4.leases";
          persist = true;
          type = "memfile";
        };
        valid-lifetime = 4000;
        renew-timer = 1000;
        rebind-timer = 2000;
        interfaces-config = {
          interfaces = ["lan"];
          service-sockets-max-retries = -1;
        };
        option-data = [
          {
            name = "domain-name-servers";
            data = "1.1.1.1, 8.8.8.8";
          }
        ];
        subnet4 = [
          {
            interface = "lan";
            subnet = cidr.canonicalize net.lan.ipv4cidr;
            pools = [
              {pool = "192.168.100.20 - 192.168.100.250";}
            ];
            option-data = [
              {
                name = "routers";
                data = cidr.ip net.lan.ipv4cidr;
              }
            ];
            #reservations = [
            #  {
            #    duid = "aa:bb:cc:dd:ee:ff";
            #    ip-address = cidr.ip net.lan.ipv4cidr;
            #  }
            #];
          }
        ];
      };
    };
    #dhcp6 = {
    #  enable = true;
    #};
  };
  systemd.services.kea-dhcp4-server.after = [
    "sys-subsystem-net-devices-lan.device"
  ];

  #extra.wireguard.vms = {
  #  server = {
  #    enable = true;
  #    host = "192.168.1.231";
  #    port = 51822;
  #    openFirewall = true;
  #  };
  #  addresses = ["10.0.0.1/24"];
  #};
}
