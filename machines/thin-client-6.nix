{ ... }:

{
  # Override printers for thin-client-6. Replace with the actual device URIs
  # from `lpinfo -v` on that host.
  thinClients.sifos = {
    printers = [
      {
        name = "thinclient-6-DA210";
        # Printing to the DA210 hosted on thin-client-4 over IPP.
        deviceUri = "ipp://192.168.1.163:631/printers/thinclient-4-DA210";
        model = "raw";
      }
    ];
    defaultPrinter = "thinclient-6-DA210";
    # Open IPP for CUPS; add 515 only if you run cups-lpd for legacy LPR.
    openTcpPorts = [ 22 3389 631 ];
  };
}
