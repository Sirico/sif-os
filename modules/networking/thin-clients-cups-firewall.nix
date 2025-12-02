# SifOS Thin Client: CUPS sharing + firewall defaults
{ config, lib, pkgs, ... }:

let
  cfg = config.thinClients.sifos;
in
{
  options.thinClients.sifos = {
    enable = lib.mkEnableOption "SifOS thin-client CUPS sharing + firewall defaults";

    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "*:631" "localhost:631" ];
      description = "Addresses/ports CUPS should listen on for IPP (631).";
    };

    allowFrom = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "localhost" ];
      description = "Networks allowed to talk to cupsd.";
    };

    openTcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ 22 3389 631 ];
      description = "TCP ports to open in the firewall on thin-clients.";
    };

    printers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            example = "DA210";
            description = "Queue name.";
          };
          location = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "Dispatch Desk";
            description = "Optional human-readable location.";
          };
          description = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "Godex DA210 (USB)";
            description = "Optional human-readable description.";
          };
          deviceUri = lib.mkOption {
            type = lib.types.str;
            example = "usb://GoDEX/DA210?serial=12345678";
            description = "CUPS device URI (see `lpinfo -v`).";
          };
          model = lib.mkOption {
            type = lib.types.str;
            default = "raw";
            example = "raw";
            description = "PPD/driver for the queue (use `raw` for driverless passthrough).";
          };
          ppdOptions = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            example = {
              PageSize = "Custom.100x150mm";
              media = "labels";
            };
            description = "PPD options for the queue.";
          };
        };
      });
      default = [ ];
      description = "Printer queues to enforce on all thin-clients.";
    };

    defaultPrinter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "DA210";
      description = "Default printer queue name (optional).";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkDefault cfg.openTcpPorts;

    services.avahi = {
      enable = lib.mkDefault true;
      nssmdns4 = lib.mkDefault true;
      publish = {
        enable = lib.mkDefault true;
        userServices = lib.mkDefault true;
      };
    };

    services.printing = {
      enable = lib.mkDefault true;
      webInterface = lib.mkDefault true;
      defaultShared = lib.mkForce true;
      browsing = lib.mkForce true;
      listenAddresses = lib.mkForce cfg.listenAddresses;
      allowFrom = lib.mkForce cfg.allowFrom;
      startWhenNeeded = lib.mkDefault true;
      drivers = lib.mkDefault [ ];
    };

    hardware.printers.ensurePrinters = cfg.printers;
    hardware.printers.ensureDefaultPrinter = cfg.defaultPrinter;
  };
}
