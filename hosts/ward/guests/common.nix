{nodes, ...}: let
  sentinelCfg = nodes.sentinel.config;
in {
  meta.wireguard-proxy.sentinel = {};
  meta.promtail = {
    enable = true;
    proxy = "sentinel";
  };

  # Connect safely via wireguard to skip http authentication
  networking.hosts.${sentinelCfg.meta.wireguard.proxy-sentinel.ipv4} = [sentinelCfg.networking.providedDomains.influxdb];
  meta.telegraf = {
    enable = true;
    scrapeSensors = false;
    influxdb2 = {
      domain = sentinelCfg.networking.providedDomains.influxdb;
      organization = "servers";
      bucket = "telegraf";
      node = "ward-influxdb";
    };
  };
}
