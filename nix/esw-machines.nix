self: system:
{ lib, config, ... }:
let
  inherit (lib) mkEnableOption mkOption;
  inherit (lib.types) port str package path;
  cfg = config.services.esw-machines;
  dataFileDir = builtins.dirOf cfg.dataFilePath;
  defaultServiceConfig = {
    Type = "oneshot";
    User = cfg.user;
    Group = config.users.users.${cfg.user}.group;
    WorkingDirectory = "${cfg.package}/bin";
    AmbientCapabilities = "CAP_NET_BIND_SERVICE";
  };
in {
  options.services.esw-machines = {
    enable = mkEnableOption "esw-machines";
    port = mkOption { type = port; };
    domain = mkOption { type = str; };
    package = mkOption {
      type = package;
      default = self.packages.${system}.default;
    };
    user = mkOption {
      type = str;
      default = "esw-machine";
    };
    dataFilePath = mkOption { type = path; };
  };

  config = {
    users.users."${cfg.user}" = lib.mkDefault {
      description = "esw-machine user";
      isSystemUser = true;
      group = "${cfg.user}";
    };
    users.groups."${cfg.user}" = lib.mkDefault { };

    systemd.services.esw-machines = {
      restartIfChanged = true;
      wantedBy = [ "multi-user.target" ];
      serviceConfig = defaultServiceConfig;
      script = ''
        pwd
        mkdir -p ${dataFileDir}
        touch  ${cfg.dataFilePath}
        ${cfg.package.outPath}/bin/esw-machines
      '';
      #${getExe cfg.package}
      environment = {
        LEPTOS_SITE_ADDR = "${cfg.domain}:${toString cfg.port}";
        LEPTOS_SITE_ROOT="${cfg.package}/bin/site";
        LEPTOS_DB_FILE = cfg.dataFilePath;

      };
    };
  };
}
