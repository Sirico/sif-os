{ ... }:

{
  thinClients.sifos = {
    printers = [
      {
        name = "thinclient-4-DA210";
        deviceUri = "usb://TSC/DA210?serial=000001";
        model = "raw";
      }
    ];
    defaultPrinter = "thinclient-4-DA210";
    # Open LPR/IPP so Windows LPR ports can reach CUPS.
    openTcpPorts = [ 22 3389 515 631 ];
  };
}
