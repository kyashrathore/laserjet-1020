# LaserJet 1020

A small Mac app for printing PDFs on an HP LaserJet 1020 (or 1020 Plus) over USB, including manual two-sided printing.

- One side, both sides (manual), or back sides only, for any page selection such as `5-12` or `1, 3, 7-9`.
- Two-sided: the fronts print first; you move the output stack, as it is, to the upper tray and the backs print in the order and orientation that stack needs. With an odd page count, the first sheet passes through with a blank back.
- Loads the printer's firmware, which the 1020 keeps only in RAM, from the app or automatically when the printer is switched on.
- Shows the print queue, keeps it to one job, and lets you cancel, resume or see the error of a stuck job.

Requires a Mac with Apple silicon on macOS 14 or later.

## Install

Connect the printer by USB, switch it on, and run this in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/kyashrathore/laserjet-1020/main/install.sh | bash
```

It asks for your Mac password once, to install the driver. Run it again at any time to update the app; steps already done are skipped.

[`install.sh`](install.sh) does this:

1. Installs Rosetta if it's missing. If the Xcode command line tools are missing, it opens their installer and stops; run the command again once they're in.
2. Puts this repository in `~/Library/Printers/HP LaserJet 1020/App`, or updates it there.
3. **HP driver.** HP never made a 1020 driver for current macOS. Apple's last HP driver package, [HP Printer Drivers 5.1.1](https://support.apple.com/en-us/106385), has the LaserJet 1022 driver, which drives the 1020 once the firmware is loaded. The script downloads it from Apple, checks its checksum and Apple's signature, lifts its two install checks (see [What is patched](#what-is-patched)) and installs it.
4. **Firmware.** Downloads HP's firmware image, [sihp1020.tar.gz](https://foo2zjs.linkevich.net/foo2zjs/firmware/sihp1020.tar.gz), from the [foo2zjs](https://foo2zjs.linkevich.net/) project, and converts it with foo2zjs's `arm2hpdl` (from [foo2zjs.tar.gz](https://foo2zjs.linkevich.net/foo2zjs/foo2zjs.tar.gz)) into `~/Library/Printers/HP LaserJet 1020/sihp1020.dl`, the file the printer takes. Both the download and the result are checked against known checksums. The firmware isn't in this repository.
5. **Printer queue.** Finds the printer on USB and adds the print queue `HP_LaserJet_1020` with the LaserJet 1022 driver, on Letter paper in the US, Canada, Mexico and the Philippines and A4 elsewhere.
6. **App.** Runs [`build.sh`](build.sh), which compiles the app into `~/Applications/LaserJet 1020.app` and adds **Open in LaserJet 1020** to the PDF menu of every Print window.

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

The package refused macOS newer than 15.0; the check is turned off. Repacking with `pkgutil --flatten` drops Apple's signature, so the script installs it with `installer -allowUntrusted`, after checking the signature of the original.

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
