# Dispatch Bench Printer Setup
Applies to any dispatch-X pair:

- `thin-client-X` – NixOS thin client with USB label printer (CUPS)
- `vm-X` – Windows VM running Shipster

## 0) Hardening so it survives outages
- Reserve DHCP leases for `thin-client-X` and `vm-X` so the LAN IP in the CUPS URL never changes after a power cut.
- Thin clients already open IPP in the firewall (`services.printing.openFirewall = true`) and listen on `*:631`; keep them up to date with `nixos-rebuild switch --flake .#thin-client-X`.
- Keep a small table per bench: expected LAN IP + queue name (e.g. `192.168.1.159` ↔ `thin-client-6-DA210`).
- If IPP is down but you must ship, you can temporarily add the printer via SMB: `\\thin-client-X\<queue-name>` (Samba sharing is enabled on thin clients).

## 1) Set up the printer on the thin client (CUPS)
On `thin-client-X`:

```
lpstat -p
lpstat -v
```

Look for a queue like:

```
printer thin-client-X-DA210 is idle...
device for thin-client-X-DA210: brusb://...
```

The part after `printer` is the queue name (e.g. `thin-client-5-DA210`).

Find the LAN IP (ignore the 100.x.x.x Tailscale IP):

```
hostname -I
```

Test a print from the thin client:

```
lp -d thin-client-X-DA210 /etc/services
```

If that prints, the CUPS queue is good. You now have:

- Queue name: `thin-client-X-DA210`
- LAN IP: `192.168.x.x`

## 2) Add the printer on the Windows VM (vm-X)
On `vm-X`:

- Settings → Devices → Printers & scanners.
- Turn off **Let Windows manage my default printer**.
- Add a printer → **The printer that I want isn’t listed**.
- Choose **Select a shared printer by name** and enter:

```
http://192.168.x.x:631/printers/thin-client-X-DA210
```

Replace with the real IP + queue name. Pick the correct label printer driver (e.g. TSC DA210 / Citizen). Name it something clear, e.g. `Printer for thinclient X @ thin-client-X`.

After adding:

- Manage → Printer properties.
- **Ports**: confirm it uses the `http://192.168...` port (not WSD-xxxx).
- **General**: Print Test Page; ensure it prints.

## 3) Point Shipster at the printer
On `vm-X`:

- Shipster → Settings → Printers → Default Printers → Edit each relevant entry (A4, label/Citizen/Zebra).
- Set **Printer** to `Printer for thinclient X @ thin-client-X`.
- OK, then (once) **Push to all machines** if this VM is the master config.
- Courier Settings → DG settings… → Print Rules → for each rule, set the same printer. Save and restart Shipster, then print a test DG label.

## 4) Troubleshooting
### 4.1 Forbidden in the browser
Symptom: Forbidden visiting `http://100.x.x.x:631/...` (Tailscale IP).

Use the LAN IP instead:

```
http://192.168.x.x:631/printers/thin-client-X-DA210
```

### 4.2 Windows test page doesn’t print
- **Port type**: In Printer properties → Ports, it must be `http://192.168.x.x:631/printers/thin-client-X-DA210`. If not, delete and re-add.
- **CUPS working?** On `thin-client-X`: `lp -d thin-client-X-DA210 /etc/services`.
- **Queue stuck?** Clear jobs in Windows; in CUPS: `cancel -a thin-client-X-DA210`.

### 4.3 Shipster error: printer not valid / keeps reverting
- Ensure no old printer names in Shipster: Settings → Printers → Default Printers and DG Print Rules.
- Make sure only one VM is the “master” that runs **Push to all machines**.
- Keep “Let Windows manage my default printer” OFF on all Shipster VMs.

### 4.4 Labels drift out of alignment
- Calibrate the printer (gap/black mark) using the printer’s button procedure.
- Match page size in CUPS and in the Windows driver (e.g. 100×150 mm / 4×6").
- Keep scaling at 100% in Shipster; use margins only for small tweaks.

### 4.5 Jobs show “Attention required” in Windows
- Clear the queue (Windows and CUPS).
- Power-cycle the label printer.
- On `thin-client-X`: `sudo systemctl restart cups` and retry the Windows test page.

### 4.6 After a power cut: quick recovery checklist
On `thin-client-X` (as admin):

```
hostname -I              # confirm LAN IP hasn’t changed
sudo systemctl status cups
sudo ss -ltnp | grep :631  # cupsd should listen on 0.0.0.0:631
sudo nft list ruleset | grep 631  # firewall rule present
```

If cupsd isn’t listening, restart: `sudo systemctl restart cups`. If the IP changed, re-add the printer in Windows to the new IP and then fix DHCP reservations so it doesn’t change again.

From `vm-X`:

```
Test-NetConnection 192.168.x.x -Port 631 -InformationLevel Detailed
```

If that fails, verify the thin client is up and that its IP matches what you expect. Once port 631 is reachable, re-open Printer properties → Print Test Page, then Shipster test label.
