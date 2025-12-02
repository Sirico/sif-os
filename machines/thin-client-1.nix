{ ... }:

{
  # Override printers for thin-client-1. Replace with the actual device URIs
  # from `lpinfo -v` on that host.
  thinClients.sifos = {
    printers = [
      # {
      #   name = "DA210";
      #   deviceUri = "usb://TSC/DA210?serial=REPLACE_ME";
      #   model = "raw";
      # }
    ];
    defaultPrinter = null;
  };
}
