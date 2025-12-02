{ ... }:

{
  thinClients.sifos = {
    printers = [
      {
        name = "DA210";
        deviceUri = "usb://TSC/DA210?serial=000001";
        model = "raw";
      }
    ];
    defaultPrinter = "DA210";
  };
}
