# LaserJet 1020

A small Mac app for printing PDFs on an HP LaserJet 1020 (or 1020 Plus) over USB, including manual two-sided printing.

- One side, both sides (manual), or back sides only, for any page selection such as `5-12` or `1, 3, 7-9`.
- Two-sided: the fronts print first; you move the output stack, as it is, to the upper tray and the backs print in the order and orientation that stack needs. With an odd page count, the first sheet passes through with a blank back.
- Loads the printer's firmware, which the 1020 keeps only in RAM, from the app or automatically when the printer is switched on.
- Shows the print queue, keeps it to one job, and lets you cancel, resume or see the error of a stuck job.

Requires macOS 14 or later on Apple silicon and the Xcode command line tools (`xcode-select --install`).

## Install

### 1. HP driver

HP never made a 1020 driver for current macOS. Apple's last HP driver package (5.1.1) has the LaserJet 1022 driver, which drives the 1020 once the firmware is loaded. The package refuses to install on macOS newer than 15 and on Apple silicon, so the steps below lift those two checks and repack it (see [What is patched](#what-is-patched)). The driver is Intel code and runs under Rosetta.

```bash
softwareupdate --install-rosetta --agree-to-license
```

```bash
mkdir -p ~/Downloads/laserjet-1020 && cd ~/Downloads/laserjet-1020
curl -fLO https://updates.cdn-apple.com/2021/macos/071-46903-20211101-0BD2764A-901C-41BA-9573-C17B8FDC4D90/HewlettPackardPrinterDrivers.dmg
hdiutil attach -nobrowse -readonly -mountpoint mnt HewlettPackardPrinterDrivers.dmg
pkgutil --expand mnt/HewlettPackardPrinterDrivers.pkg expanded
hdiutil detach mnt
sed -i '' -e "s/system.compareVersions(system.version.ProductVersion, '15.0') \&gt; 0/false/" -e 's/hostArchitectures="x86_64"/hostArchitectures="x86_64,arm64"/' expanded/Distribution
pkgutil --flatten expanded HP-patched.pkg
```

Repacking removes Apple's signature, so the installer needs `-allowUntrusted`:

```bash
sudo installer -pkg ~/Downloads/laserjet-1020/HP-patched.pkg -target / -allowUntrusted
```

Apple describes the package on [HP Printer Drivers v5.1.1 for macOS](https://support.apple.com/en-us/106385).

### 2. Firmware

The firmware isn't in this repository. It comes from the [foo2zjs](https://foo2zjs.linkevich.net/) project: [sihp1020.tar.gz](https://foo2zjs.linkevich.net/foo2zjs/firmware/sihp1020.tar.gz) holds HP's firmware image, and foo2zjs's `arm2hpdl` (in [foo2zjs.tar.gz](https://foo2zjs.linkevich.net/foo2zjs/foo2zjs.tar.gz)) wraps it into the `sihp1020.dl` file the printer takes. The app reads it from `~/Library/Printers/HP LaserJet 1020/sihp1020.dl`.

```bash
cd ~/Downloads/laserjet-1020
curl -fLO https://foo2zjs.linkevich.net/foo2zjs/firmware/sihp1020.tar.gz
curl -fLO https://foo2zjs.linkevich.net/foo2zjs/foo2zjs.tar.gz
tar -xzf sihp1020.tar.gz
tar -xzf foo2zjs.tar.gz foo2zjs/arm2hpdl.c
cc -O2 -w -o arm2hpdl foo2zjs/arm2hpdl.c
mkdir -p ~/Library/Printers/"HP LaserJet 1020"
./arm2hpdl sihp1020.img > ~/Library/Printers/"HP LaserJet 1020"/sihp1020.dl
```

`shasum -a 256` of the files that work:

```
ec4665c6704c2db3cfaeb71bb06f1bbc9449c030504b04f533a84bdfae89f966  sihp1020.tar.gz
133b21fe0cb24bfe53e2eff2f00a82cce4beb970749049661ade7a6801f22663  sihp1020.dl
```

### 3. Printer queue

Connect the printer by USB and switch it on. Find its address:

```bash
lpinfo -v | grep -i "laserjet%201020"
```

Add the queue with that address in place of the one below. The app expects the queue name `HP_LaserJet_1020`.

```bash
lpadmin -p HP_LaserJet_1020 -D "HP LaserJet 1020" -E -v "usb://Hewlett-Packard/HP%20LaserJet%201020?serial=XXXXXXX" -m "Library/Printers/PPDs/Contents/Resources/HP LaserJet 1022.gz" -o printer-is-shared=false
```

For A4 paper:

```bash
lpadmin -p HP_LaserJet_1020 -o PageSize=A4 -o PageRegion=A4
```

### 4. The app

```bash
git clone https://github.com/kyashrathore/laserjet-1020.git
cd laserjet-1020 && ./build.sh
```

`build.sh` compiles the app, installs it as `~/Applications/LaserJet 1020.app` and adds **Open in LaserJet 1020** to the PDF menu of every Print window. Run it again after pulling changes.

## What is patched

Only the installer of Apple's HP driver package. Its `Distribution` file, which decides whether the package may install, gets two edits; the driver files it installs, the 1022 PPD, CUPS and the firmware are used unchanged.

```diff
-    <options hostArchitectures="x86_64"/>
+    <options hostArchitectures="x86_64,arm64"/>
```

The package was marked Intel-only, so Installer refused it on Apple silicon. The driver itself still runs as Intel code under Rosetta.

```diff
 function InstallationCheck(prefix) {
-	if (system.compareVersions(system.version.ProductVersion, '15.0') &gt; 0) {
+	if (false) {
 		my.result.message = system.localizedStringWithFormat('ERROR_25CBFE41C7', '15.0');
 		my.result.type = 'Fatal';
 		return false;
```

The package refused macOS newer than 15.0; the check is turned off. Repacking with `pkgutil --flatten` drops Apple's signature, hence `-allowUntrusted`.

Apple plans to phase out Rosetta, and CUPS already warns that this kind of driver is deprecated, so a future macOS may stop running it.

## Use

1. Open **LaserJet 1020** from `~/Applications`, then drop a PDF on the window or click **Choose PDF…**. From any other app, press ⌘P, open the **PDF** menu at the bottom of the Print window and choose **Open in LaserJet 1020**.
2. If the header says the printer needs its firmware, click **Load Firmware**. The printer forgets it every time it is switched off. Turn on **Load firmware automatically** at the bottom of the window to have it loaded as soon as the printer is switched on, which also makes printing from other apps work.
3. Optionally type the pages to print, then pick:
   - **One side**: a normal print.
   - **Both sides – manual**: the fronts print, then the app tells you to move the stack, as it comes out, to the tray above the blank-paper tray, and click **Print Back Sides**. Leave the lower tray empty for the back pass, or the printer may take blank paper from it.
   - **Back sides only**: for sheets whose fronts are already printed, for example after a paper jam.
4. The print queue at the bottom shows what is printing. A stuck job can be cancelled or resumed there, and **Clear All** empties the queue.

## Checks

`tests/SplitCheck.swift` checks page selection and the page order and orientation of fronts and backs against any PDF of 4 or more pages that look different from each other:

```bash
swiftc -parse-as-library -o /tmp/split-check tests/SplitCheck.swift Pages.swift Printing.swift Queue.swift && /tmp/split-check some.pdf
```
