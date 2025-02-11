{
  config,
  nodes,
  pkgs,
  ...
}: let
  inherit (sentinelCfg.repo.secrets.local) personalDomain;
  sentinelCfg = nodes.sentinel.config;
  kanidmDomain = "auth.${personalDomain}";
  kanidmPort = 8300;
in {
  meta.wireguard-proxy.sentinel.allowedTCPPorts = [kanidmPort];

  age.secrets."kanidm-self-signed.crt" = {
    rekeyFile = config.node.secretsDir + "/kanidm-self-signed.crt.age";
    mode = "440";
    group = "kanidm";
  };

  age.secrets."kanidm-self-signed.key" = {
    rekeyFile = config.node.secretsDir + "/kanidm-self-signed.key.age";
    mode = "440";
    group = "kanidm";
  };

  age.secrets.kanidm-admin-password = {
    generator.script = "alnum";
    mode = "440";
    group = "kanidm";
  };

  age.secrets.kanidm-idm-admin-password = {
    generator.script = "alnum";
    mode = "440";
    group = "kanidm";
  };

  age.secrets.kanidm-oauth2-immich = {
    generator.script = "alnum";
    generator.tags = ["oauth2"];
    mode = "440";
    group = "kanidm";
  };

  age.secrets.kanidm-oauth2-grafana = {
    generator.script = "alnum";
    generator.tags = ["oauth2"];
    mode = "440";
    group = "kanidm";
  };

  age.secrets.kanidm-oauth2-forgejo = {
    generator.script = "alnum";
    generator.tags = ["oauth2"];
    mode = "440";
    group = "kanidm";
  };

  age.secrets.kanidm-oauth2-web-sentinel = {
    generator.script = "alnum";
    generator.tags = ["oauth2"];
    mode = "440";
    group = "kanidm";
  };

  nodes.sentinel = {
    networking.providedDomains.kanidm = kanidmDomain;

    services.nginx = {
      upstreams.kanidm = {
        servers."${config.meta.wireguard.proxy-sentinel.ipv4}:${toString kanidmPort}" = {};
        extraConfig = ''
          zone kanidm 64k;
          keepalive 2;
        '';
      };
      virtualHosts.${kanidmDomain} = {
        forceSSL = true;
        useACMEWildcardHost = true;
        locations."/".proxyPass = "https://kanidm";
        # Allow using self-signed certs to satisfy kanidm's requirement
        # for TLS connections. (Although this is over wireguard anyway)
        extraConfig = ''
          proxy_ssl_verify off;
        '';
      };
    };
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/kanidm";
      user = "kanidm";
      group = "kanidm";
      mode = "0700";
    }
  ];

  services.kanidm = {
    enableServer = true;
    serverSettings = {
      domain = kanidmDomain;
      origin = "https://${kanidmDomain}";
      tls_chain = config.age.secrets."kanidm-self-signed.crt".path;
      tls_key = config.age.secrets."kanidm-self-signed.key".path;
      bindaddress = "0.0.0.0:${toString kanidmPort}";
      trust_x_forward_for = true;
    };

    enableClient = true;
    clientSettings = {
      uri = config.services.kanidm.serverSettings.origin;
      verify_ca = true;
      verify_hostnames = true;
    };

    provision = {
      enable = true;
      adminPasswordFile = config.age.secrets.kanidm-admin-password.path;
      idmAdminPasswordFile = config.age.secrets.kanidm-idm-admin-password.path;

      inherit (config.repo.secrets.global.kanidm) persons;

      # Immich
      groups.immich = {};
      systems.oauth2.immich = {
        displayName = "Immich";
        originUrl = "https://${sentinelCfg.networking.providedDomains.immich}";
        basicSecretFile = config.age.secrets.kanidm-oauth2-immich.path;
        scopeMaps.immich = ["openid" "email" "profile"];
      };

      # Grafana
      groups.grafana = {};
      groups."grafana.admins" = {};
      groups."grafana.editors" = {};
      groups."grafana.server-admins" = {};
      systems.oauth2.grafana = {
        displayName = "Grafana";
        originUrl = "https://${sentinelCfg.networking.providedDomains.grafana}";
        basicSecretFile = config.age.secrets.kanidm-oauth2-grafana.path;
        scopeMaps.grafana = ["openid" "email" "profile"];
        supplementaryScopeMaps = {
          "grafana.admins" = ["admin"];
          "grafana.editors" = ["editor"];
          "grafana.server-admins" = ["server_admin"];
        };
      };

      # Forgejo
      groups.forgejo = {};
      groups."forgejo.admins" = {};
      systems.oauth2.forgejo = {
        displayName = "Forgejo";
        originUrl = "https://${sentinelCfg.networking.providedDomains.forgejo}";
        basicSecretFile = config.age.secrets.kanidm-oauth2-forgejo.path;
        scopeMaps.forgejo = ["openid" "email" "profile"];
        supplementaryScopeMaps = {
          "forgejo.admins" = ["admin"];
        };
      };

      # Web Sentinel
      groups.web-sentinel = {};
      groups."web-sentinel.adguardhome" = {};
      groups."web-sentinel.influxdb" = {};
      systems.oauth2.web-sentinel = {
        displayName = "Web Sentinel";
        originUrl = "https://oauth2.${personalDomain}";
        basicSecretFile = config.age.secrets.kanidm-oauth2-web-sentinel.path;
        scopeMaps.web-sentinel = ["openid" "email"];
        supplementaryScopeMaps = {
          "web-sentinel.adguardhome" = ["access_adguardhome"];
          "web-sentinel.influxdb" = ["access_influxdb"];
        };
      };
    };
  };

  environment.systemPackages = [pkgs.kanidm];
  systemd.services.kanidm.serviceConfig.RestartSec = "60"; # Retry every minute
}
