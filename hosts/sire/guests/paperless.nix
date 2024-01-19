{
  config,
  nodes,
  ...
}: let
  sentinelCfg = nodes.sentinel.config;
  paperlessDomain = "paperless.${sentinelCfg.repo.secrets.local.personalDomain}";
in {
  microvm.mem = 1024 * 6;
  microvm.vcpu = 8;

  nodes.sentinel = {
    networking.providedDomains.paperless = paperlessDomain;

    services.nginx = {
      upstreams.paperless = {
        servers."${config.meta.wireguard.proxy-sentinel.ipv4}:${toString config.services.paperless.port}" = {};
        extraConfig = ''
          zone paperless 64k;
          keepalive 2;
        '';
      };
      virtualHosts.${paperlessDomain} = {
        forceSSL = true;
        useACMEWildcardHost = true;
        extraConfig = ''
          client_max_body_size 512M;
        '';
        locations."/" = {
          proxyPass = "http://paperless";
          proxyWebsockets = true;
          X-Frame-Options = "SAMEORIGIN";
        };
      };
    };
  };

  meta.wireguard-proxy.sentinel.allowedTCPPorts = [
    config.services.paperless.port
  ];

  age.secrets.paperless-admin-password = {
    rekeyFile = config.node.secretsDir + "/paperless-admin-password.age";
    generator.script = "alnum";
    mode = "440";
    group = "paperless";
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/paperless";
      user = "paperless";
      group = "paperless";
      mode = "0750";
    }
  ];

  services.paperless = {
    enable = true;
    address = "0.0.0.0";
    passwordFile = config.age.secrets.paperless-admin-password.path;
    consumptionDir = "/paperless/consume";
    mediaDir = "/paperless/media";
    settings = {
      PAPERLESS_URL = "https://${paperlessDomain}";
      PAPERLESS_ALLOWED_HOSTS = paperlessDomain;
      PAPERLESS_CORS_ALLOWED_HOSTS = "https://${paperlessDomain}";
      PAPERLESS_TRUSTED_PROXIES = sentinelCfg.meta.wireguard.proxy-sentinel.ipv4;

      PAPERLESS_CONSUMER_ENABLE_BARCODES = true;
      PAPERLESS_CONSUMER_ENABLE_ASN_BARCODE = true;
      PAPERLESS_CONSUMER_BARCODE_SCANNER = "ZXING";
      PAPERLESS_CONSUMER_RECURSIVE = true;
      PAPERLESS_FILENAME_FORMAT = "{owner_username}/{created_year}-{created_month}-{created_day}_{asn}_{title}";

      # Nginx does that better.
      PAPERLESS_ENABLE_COMPRESSION = false;

      #PAPERLESS_IGNORE_DATES = concatStringsSep "," ignoreDates;
      PAPERLESS_NUMBER_OF_SUGGESTED_DATES = 8;
      PAPERLESS_OCR_LANGUAGE = "deu+eng";
      PAPERLESS_TASK_WORKERS = 4;
      PAPERLESS_WEBSERVER_WORKERS = 4;
    };
  };

  systemd.services.paperless.serviceConfig.RestartSec = "600"; # Retry every 10 minutes
}
