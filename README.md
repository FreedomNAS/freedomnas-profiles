# FreedomNAS Profiles

I file di traduzione OS specifici per FreedomNAS.

## Profili Disponibili

- **debian.json**: Debian, Ubuntu, basati su Debian
- **freebsd.json**: FreeBSD 13.0+
- **arch.json**: Arch Linux (community-maintained)

## Struttura della Repository

```
freedomnas-profiles/
├── debian.json             ← Profilo OS: comandi per Debian/Ubuntu
├── freebsd.json            ← Profilo OS: comandi per FreeBSD
├── arch.json                ← Profilo OS: comandi per Arch Linux
├── init/                    ← Profili init-system, separati dall'OS
│   ├── systemd.json
│   ├── openrc.json
│   ├── runit.json
│   ├── s6.json
│   ├── dinit.json
│   └── bsd_rc.json
└── packages/                ← Pacchetti opzionali, a categorie
    ├── MANIFEST.json         ← elenco categorie disponibili
    ├── SCHEMA.md              ← formato completo
    ├── core.json              ← pacchetti NAS essenziali (richiesto)
    ├── samba-cifs.json
    ├── nfs.json
    ├── containers.json
    └── virtualization.json
```

## Cosa Sono i Profili?

Ogni profilo OS (`debian.json`, `freebsd.json`, `arch.json`) è un file JSON che mappa
azioni astratte ai comandi nativi del sistema operativo — gestione utenti, rete, ZFS,
Samba, NFS, boot chain, ecc.

**Esempio (categoria `zfs`):**

```json
"zfs": {
  "pool_import": "zpool import -d /dev/disk/by-id {pool_name}",   // Debian
  "snapshot_create": "zfs snapshot {dataset}@{snap_name}"
}
```

Su FreeBSD lo stesso file avrebbe gli stessi nomi di azione, con comandi diversi dove
necessario (es. `packages.install` è `apt install -y {package_name}` su Debian e
`pkg install -y {package_name}` su FreeBSD).

### Init-agnostic: `services` non è più nel profilo OS

La gestione dei servizi (`start`, `stop`, `restart`, `enable`, ...) è stata separata
dal profilo OS ed è ora definita per init-system in `init/{init_system}.json`
(systemd, OpenRC, runit, s6, dinit, bsd_rc). Il motore rileva l'init system in
esecuzione (marker su filesystem, con fallback al campo `init_system` dichiarato nel
profilo OS) e unisce il profilo init a quello OS a runtime — così la stessa Debian
può girare con systemd o, in futuro, con un init diverso, senza toccare `debian.json`.

### Pacchetti opzionali: `packages/`

I pacchetti non-essenziali (Samba, NFS, container, virtualizzazione) non sono più
elencati direttamente nei profili OS, ma in file separati sotto `packages/`, uno per
categoria, elencati in `packages/MANIFEST.json`. Questo permette all'installer/WebUI
di offrire feature opzionali selezionabili, e ai backup di ricordare quali categorie
erano installate per un disaster recovery cross-distro. Vedi `packages/README.md` e
`packages/SCHEMA.md` per i dettagli completi.

## Come il Core Engine Usa i Profili

1. Rileva il sistema operativo (`debian` | `freebsd` | `arch`)
2. Carica il profilo OS corrispondente (`{os}.json`)
3. Rileva l'init system in esecuzione e unisce `init/{init_system}.json`
4. Traduce le azioni astratte ai comandi nativi
5. Esegue i comandi in sicurezza (mai `shell=True` senza necessità, mai comandi
   costruiti a mano nel codice Python — vedi la "Golden Rule" in ARCHITECTURE.md)

```python
from freedomnas.engine import get_engine

engine = get_engine()

# Su Debian: systemctl restart samba
# Su FreeBSD: service samba restart
# Su Arch: systemctl restart samba
engine.execute("services", "restart", service_name="samba")

# Ottenere solo il comando risolto, senza eseguirlo
cmd = engine.get_command("bootloader", "build_uki",
                          dataset="rpool/ROOT/debian",
                          output_path="/boot/efi/EFI/Linux/debian-uki.efi",
                          kernel_version="6.1.0-amd64")
```

## Aggiungere una Nuova Distribuzione

Vedi [CONTRIBUTING.md](CONTRIBUTING.md) per una guida completa.

## Struttura di un Profilo OS

```json
{
  "os_name": "Distribution Name",
  "os_family": "linux|bsd",
  "os_version": "version_spec",
  "init_system": "systemd",

  "users": { /* gestione utenti */ },
  "network": { /* configurazione rete */ },
  "packages": { /* comandi del package manager (apt/pkg/pacman) */ },
  "zfs": { /* comandi ZFS */ },
  "samba": { /* comandi Samba/SMB */ },
  "nfs": { /* comandi NFS */ },
  "btrfs": { /* comandi Btrfs — dove supportato */ },
  "bootloader": { /* build UKI (dracut) + registrazione boot UEFI (efibootmgr) */ },
  "system": { /* info/controllo di sistema */ }
}
```

`services` **non** va qui — vive in `init/{init_system}.json` (vedi sopra).

### `bootloader`

FreedomNAS boota da un Unified Kernel Image (UKI) costruito con `dracut`, caricato
direttamente via `efibootmgr` su UEFI nativo. Su BIOS legacy, l'installer usa Clover
(vendorizzato in `freedomnas-installer/assets/clover/`) per emulare UEFI — quella
parte è puro I/O su file, non richiede comandi di profilo. Il profilo espone solo i
due comandi OS-nativi:

```json
"bootloader": {
  "build_uki": "dracut --force --uefi --kernel-cmdline \"root=ZFS={dataset} rw\" {output_path} {kernel_version}",
  "efi_boot_entry": "efibootmgr --create --disk {disk} --part {part_num} --loader {loader_path} --label {label}"
}
```

Attualmente presente solo in `debian.json`; `freebsd.json` e `arch.json` mantengono
ancora la loro configurazione boot esistente.

Vedi i file JSON per esempi completi di ogni categoria.
