{ lib, config, esw-package, leptos-options, ... }:
let
  inherit (lib) mkEnableOption mkOption getExe;
  inherit (lib.types) port str package path;
  cfg = config.services.esw-machines;
  dataFileDir = builtins.dirOf cfg.dataFilePath;
  defaultServiceConfig = {
    #ReadWritePaths = "${cfg.dataFilePath} ${cfg.package}";
    #DeviceAllow = "";
    #LockPersonality = true;
    #NoNewPrivileges = true;
    #PrivateDevices = true;
    #PrivateTmp = true;
    #PrivateUsers = true;
    #ProcSubset = "pid";
    #ProtectClock = true;
    #ProtectControlGroups = true;
    #ProtectHome = true;
    #ProtectHostname = true;
    #ProtectKernelLogs = true;
    #ProtectKernelModules = true;
    #ProtectKernelTunables = true;
    #ProtectProc = "invisible";
    #ProtectSystem = "strict";
    #RemoveIPC = true;
    #RestrictNamespaces = true;
    #RestrictRealtime = true;
    #RestrictSUIDSGID = true;
    #SystemCallArchitectures = "native";
    #SystemCallFilter = [ "@system-service" "~@resources" "~@privileged" ];
    #UMask = "0007";
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
        LEPTOS_OUTPUT_NAME = leptos-options.output-name;
        LEPTOS_SITE_ROOT = "site";
        LEPTOS_SITE_PKG_DIR = "pkg";
        LEPTOS_ENV = "DEV"; # TODO check if this should be enabled
        LEPTOS_DB_FILE = cfg.dataFilePath;

      };
    };
  };
}
