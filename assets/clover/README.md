# Vendored Clover binaries

Source: [CloverHackyColor/CloverBootloader](https://github.com/CloverHackyColor/CloverBootloader) release **5173**.

These exact files are pinned deliberately, not fetched at build/install time. Release 5163 (and
presumably others near it) is a known regression on some real BIOS hardware — see
[CloverBootloader#740](https://github.com/CloverHackyColor/CloverBootloader/issues/740) — while 5173
is validated working (real hardware + VM) with the `config.plist` this installer generates. Do not
bump the vendored version without re-running the hardware validation.

| File            | Role                                                              |
|------------------|--------------------------------------------------------------------|
| `boot0ss`        | MBR boot0 stage (first 440 bytes written to the disk's MBR)         |
| `boot1f32alt`    | FAT32 boot1/VBR stage (BPB-preserving merge into the ESP's boot sector) |
| `boot7`          | DUET firmware, BiosBlockIO variant (legacy-BIOS-INT13h based, avoids DUET's native AHCI/ATA driver stack) — deployed to the ESP root as `boot` |
| `CLOVERX64.efi`  | Clover's picker/BDS, deployed to `EFI/CLOVER/CLOVERX64.efi`         |
| `BOOTX64.efi`    | Generic UEFI fallback stub, deployed to `EFI/BOOT/BOOTX64.efi`      |

SHA-256 checksums at time of vendoring:
```
03ac8b82eb7344dd564181ab8fd5ba12cede50b48b6a9740a38fb934d25eb4a8  boot0ss
92749a8e42fa5819d2037723bf7b1688e99717e12dd5c0c11d992e8484a67455  boot1f32alt
5ea950b3e7ce6baca0cdf434a40758aa57eb185b29471d7e6c5e428352a2fce3  boot7
c6d8e870814387736c886a7e9b6e69a703bfd4e8b02286b636ae72f6e655a404  BOOTX64.efi
c6d8e870814387736c886a7e9b6e69a703bfd4e8b02286b636ae72f6e655a404  CLOVERX64.efi
```
