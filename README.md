# LaserJet 1020

A small Mac app for printing PDFs on an HP LaserJet 1020 over USB, including manual two-sided printing.

- One side, both sides (manual), or back sides only, for any page selection such as `5-12` or `1, 3, 7-9`.
- Two-sided: the fronts print first; you move the output stack, as it is, to the upper tray and the backs print in the order and orientation that stack needs. With an odd page count, the first sheet passes through with a blank back.
- Loads the printer's firmware, which the 1020 keeps only in RAM, from the app or automatically when the printer is connected.
- Shows the print queue, keeps it to one job, and lets you cancel, resume or see the error of a stuck job.

## Setup

1. Install Apple's HP Printer Drivers and add a CUPS queue named `HP_LaserJet_1020` with the **LaserJet 1022** driver.
2. Put the 1020 firmware at `~/Library/Printers/HP LaserJet 1020/sihp1020.dl`. It isn't in this repository; the foo2zjs project's `getweb 1020` and `arm2hpdl` produce it.
3. Run `./build.sh`. It installs `~/Applications/LaserJet 1020.app` and an "Open in LaserJet 1020" entry in the PDF menu of the print dialog.

Requires macOS 14 on Apple silicon and the Xcode command line tools.

## Checks

```sh
swiftc -parse-as-library -o /tmp/split tests/SplitCheck.swift Pages.swift Printing.swift Queue.swift && /tmp/split some-4-page-or-longer.pdf
```
