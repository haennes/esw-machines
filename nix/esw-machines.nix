{ lib, config, esw-package, leptos-options, ... }:
let
  inherit (lib) mkEnableOption mkOption getExe;
  inherit (lib.types) port str package path;
  cfg = config.services.esw-machines;
in {
  options.services.esw-machines = {
    enable = mkEnableOption "esw-machines";
    port = mkOption { type = port; };
    domain = mkOption { type = str; };
    package = mkOption {
      type = package;
      default = esw-package;
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
      wantedBy = [ "multi-user.target" ];
      script = ''
        pwd
        mkdir -p ${builtins.dirOf cfg.dataFilePath}
        touch  ${cfg.dataFilePath}
        ${cfg.package.outPath}/bin/esw-machines
      '';
      #${getExe cfg.package}
      environment = {
        LEPTOS_SITE_ADDR = "${cfg.domain}:${toString cfg.port}";
        LEPTOS_OUTPUT_NAME = leptos-options.output-name;
        #LEPTOS_SITE_ROOT = "${cfg.package.outPath}/bin/site";
        LEPTOS_SITE_ROOT = "site";
        #LEPTOS_SITE_PKG_DIR = "${cfg.package.outPath}/bin/site/pkg";
        LEPTOS_SITE_PKG_DIR = "pkg";
        LEPTOS_ENV = "DEV"; # TODO check if this should be enabled
        LEPTOS_DB_FILE = cfg.dataFilePath;

      };
      serviceConfig.WorkingDirectory = "${cfg.package}/bin";
    };
  };
}
