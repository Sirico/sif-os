{
  description = "SifOS - Multi-Purpose NixOS System with Fleet Management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    
    # Optional: Reference your personal nixos-config for darren-workstation
    # personal-config = {
    #   url = "path:/home/darren/nixos-config";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, ... } @ inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # Allow the bundled DA-210 driver (unfree) while keeping other
        # outputs free by default.
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [ "tsc-da210-barcode-driver" ];
      };
      # Fallback hardware stub to satisfy evaluation for generic targets.
      hardwareDefault = { lib, ... }: {
        # Dummy root FS; should be overridden by real hardware configs in
        # deployed systems.
        fileSystems."/" = lib.mkDefault {
          device = "/dev/disk/by-uuid/PLACEHOLDER";
          fsType = "ext4";
        };
      };
      
      # Common module imports for all SifOS machines
      commonModules = [
        ./modules/users.nix
        ./modules/remote-access.nix
        ./modules/printing.nix
        ./modules/branding.nix
      ];
      
      # Function to create a SifOS configuration
      mkSifOSSystem = hostname: machineType: extraModules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs self; };
          modules = commonModules ++ [
            ./configuration.nix
            machineType
            {
              networking.hostName = hostname;
            }
          ] ++ extraModules;
        };
    in
    {
      packages.x86_64-linux =
        {
          tsc-da210-barcode-driver = import ./packages/da210-driver.nix { inherit pkgs; };
        }
        // {
          # Convenience aliases so `nix build .#sifos-thin-client-4` works.
          sifos-thin-client-4 = self.nixosConfigurations."sifos-thin-client-4".config.system.build.toplevel;
          sifos-thin-client-6 = self.nixosConfigurations."sifos-thin-client-6".config.system.build.toplevel;
          thin-client-4 = self.nixosConfigurations."thin-client-4".config.system.build.toplevel;
          thin-client-6 = self.nixosConfigurations."thin-client-6".config.system.build.toplevel;
        };

      # Machine configurations
      nixosConfigurations = {
        # Thin clients
        "thin-client-4" = mkSifOSSystem "sifos-thin-client-4" ./machine-types/thin-client.nix [
          ./nixos/hardware-configuration-thin-client-4.nix
          ./machines/thin-client-4.nix
          { sifos.tailscale.advertiseAddress = "100.71.208.113"; }
        ];
        "sifos-thin-client-4" = mkSifOSSystem "sifos-thin-client-4" ./machine-types/thin-client.nix [
          ./nixos/hardware-configuration-thin-client-4.nix
          ./machines/thin-client-4.nix
          { sifos.tailscale.advertiseAddress = "100.71.208.113"; }
        ];
        # Thin clients
        "thin-client-6" = mkSifOSSystem "sifos-thin-client-6" ./machine-types/thin-client.nix [
          ./nixos/hardware-configuration-thin-client-6.nix
          ./machines/thin-client-6.nix
          { sifos.tailscale.advertiseAddress = "100.78.103.61"; }
        ];
        "sifos-thin-client-6" = mkSifOSSystem "sifos-thin-client-6" ./machine-types/thin-client.nix [
          ./nixos/hardware-configuration-thin-client-6.nix
          ./machines/thin-client-6.nix
          { sifos.tailscale.advertiseAddress = "100.78.103.61"; }
        ];
        
        # Office machines
        "sifos-office-1" = mkSifOSSystem "sifos-office-1" ./machine-types/office.nix [
          hardwareDefault
        ];
        
        # Workstations
        "sifos-workstation-1" = mkSifOSSystem "sifos-workstation-1" ./machine-types/workstation.nix [
          hardwareDefault
        ];
        
        # Personal workstation (can optionally import from personal-config)
        "darren-workstation" = mkSifOSSystem "darren-workstation" ./machine-types/darren-workstation.nix [
          hardwareDefault
        ];
        
        # Servers
        "sifos-server-1" = mkSifOSSystem "sifos-server-1" ./machine-types/server.nix [
          hardwareDefault
        ];
        
        # Shop kiosks
        "sifos-kiosk-1" = mkSifOSSystem "sifos-kiosk-1" ./machine-types/shop-kiosk.nix [
          hardwareDefault
        ];
        # Recovery / rescue machine type
        "recovery-thin-client" = mkSifOSSystem "recovery-thin-client" ./machine-types/recovery.nix [
          hardwareDefault
        ];
      };
      
      # Deployment helpers
      apps.${system} = {
        # Deploy to fleet via Tailscale
        fleet-deploy = {
          type = "app";
          program = "${self}/fleet-deploy.sh";
        };
        
        # Enroll new machine
        enroll = {
          type = "app";
          program = "${self}/enroll-machine.sh";
        };
      };
    };
}
