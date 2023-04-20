{lib, ...}: {
  networking.firewall = {
    allowedTCPPorts = [5355];
    allowedUDPPorts = [5353 5355];
  };

  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    fallbackDns = [
      "1.1.1.1"
      "2606:4700:4700::1111"
      "8.8.8.8"
      "2001:4860:4860::8844"
    ];
    llmnr = "true"; # Microsoft's version of mDNS
    extraConfig = ''
      Domains=~.
      MulticastDNS=true
    '';
  };

  system.nssDatabases.hosts = lib.mkMerge [
    (lib.mkBefore ["mdns_minimal [NOTFOUND=return]"])
    (lib.mkAfter ["mdns"])
  ];
}
