# Cisco Secure Firewall — FTDv + FMCv — libvirt/KVM

Packer templates for building Cisco **Secure Firewall Threat Defense Virtual (FTDv)** and
**Firewall Management Center Virtual (FMCv)** on the libvirt
provider, modelled on [celeroon/fortigate-vagrant-libvirt](https://github.com/celeroon/fortigate-vagrant-libvirt).

> **Disclaimer:** Cisco FTDv/FMCv images are proprietary and **not included** in this repo — download
> them yourself from Cisco under your own license/entitlement. This project only automates the build
> and is **unofficial, not affiliated with or endorsed by Cisco**.

> **Status:** `cisco-ftd-no-vagrant.pkr.hcl` runs an **unattended** build — it boots the FTDv qcow2,
> a `boot_command` drives the first-boot wizard over the console (EULA, admin password, DHCP
> management, local management), then shuts the VM down cleanly so packer finalizes the disk.
> Runs **headless (VNC) by default**; flip to a GUI window when you want to watch.

## Prerequisites

  * A Cisco account with FTDv entitlement
  * Git, Packer >= 1.7, libvirt, QEMU
  * A VNC client (to watch the console at `<host>:5901`)
  * Host with **KVM** and enough headroom: FTDv minimum is **4 vCPU / 8 GB RAM**

## Version

Built against **Cisco Secure Firewall 10.0** 

The `version` variable is only a label for the output filename, so any string works.

### FTDv sizing & interfaces (KVM)

  * **Minimum 4 vCPU / 8 GB** (FTDv5/10/20; larger tiers go 8/16, 12/24, 16/32). CPU type `host`.
  * **Needs ≥ 4 NICs to finish init**, in Cisco's required order — the template defines all four:
    `vnic0` = **Management** (`eth0` / Management0/0), `vnic1` = **reserved** (internal use / diagnostic),
    `vnic2` = **Outside** data (`GigabitEthernet0/0`), `vnic3` = **Inside** data (`Gi0/1`). With fewer it
    hangs at *"Virtual FTD requires at least 4 network interfaces…"*. (Supplying NIC `qemuargs`
    disables packer's default NIC, so all four are declared explicitly.)
  * Console: **VGA over VNC** (`<host>:5901`) — what packer `boot_command` drives, same as the
    FortiGate template. Cisco's docs also mention a serial console; if the VGA console comes up blank,
    add a `-serial "telnet:0.0.0.0:5905,server,nowait"` line to `qemuargs` (and if serial is the *only*
    console, keystroke automation isn't possible → use a day0.iso).
  * Firmware: legacy BIOS works; 10.0 greenfield can use **q35 + UEFI/Secure Boot**. If the qcow2
    won't boot on the default i440fx/SeaBIOS, switch to `machine_type = "q35"` with EFI (OVMF).

## Steps

1\. Download the **FTDv for KVM** `qcow2` from Cisco Software Download and copy it to `/var/lib/libvirt/images` (or point `image_path` at wherever it lives).

```
sudo cp Cisco_Secure_Firewall_Threat_Defense_Virtual-10.0.0-140.qcow2 /var/lib/libvirt/images/
sudo chown libvirt-qemu:kvm /var/lib/libvirt/images/Cisco_Secure_Firewall_Threat_Defense_Virtual-10.0.0-140.qcow2
```

2\. Clone this repo and `cd` in.

```
git clone https://github.com/celeroon/cisco-ftd-fmc-vagrant-libvirt
cd cisco-ftd-fmc-vagrant-libvirt
```

3\. Build.

```
packer init cisco-ftd-no-vagrant.pkr.hcl
packer build \
  -var "version=10.0.0-140" \
  -var "image_name=Cisco_Secure_Firewall_Threat_Defense_Virtual-10.0.0-140.qcow2" \
  cisco-ftd-no-vagrant.pkr.hcl
```

Packer copies the disk into `tmp_out/`, waits `boot_time` (**10m** — about how long FTDv takes to
reach the login prompt), types the first-boot wizard via `boot_command`, and shuts the VM down —
leaving a configured `tmp_out/cisco-ftd-<version>.qcow2`. The whole run fits inside `shutdown_timeout`
(default **45m**). If `tmp_out/` already exists from a previous run, add `-force` or `rm -rf tmp_out`.

### Headless vs GUI

The build runs **headless by default** (no window; VNC console on `<host>:5901`). To watch it in a
local QEMU window, enable the GUI — this needs a display on the machine running packer (a desktop,
or `ssh -X`):

```
packer build -var "gui_disabled=false" \
  -var "version=10.0.0-140" \
  -var "image_name=Cisco_Secure_Firewall_Threat_Defense_Virtual-10.0.0-140.qcow2" \
  cisco-ftd-no-vagrant.pkr.hcl
```

## The first-boot wizard (what `boot_command` automates)

`boot_command` answers the console wizard in order: log in `admin` / `Admin123` (factory default),
accept the EULA, set the new admin password to **`SuperPassword123$`**, choose IPv4 **DHCP**, keep
**local management** (FDM), then `shutdown` from the FTD CLI. To re-capture or tweak it, run with
`-var gui_disabled=false`, watch the wizard on the console, and adjust the lines/waits in the HCL.
Passwords and the wizard answers are edited directly in `boot_command`.

> **Built-image credentials:** both the FTD and FMC images log in as `admin` / **`SuperPassword123$`**
> (the factory `Admin123` is changed to this during firstboot). It's a lab default — change it after
> deploy, or edit the password in `boot_command` before building.

Override the shutdown window (e.g. slower host, or leave it up longer for poking around):

```
packer build -var "shutdown_timeout=60m" -var "version=10.0.0-140" -var "image_name=...qcow2" cisco-ftd-no-vagrant.pkr.hcl
```

## Networking & reaching the device

Packer's qemu builder uses QEMU **user-mode (SLIRP)** networking: `10.0.2.0/24`, gateway `10.0.2.2`,
DNS `10.0.2.3`, guest DHCPs **`10.0.2.15`** — FTDv management `eth0` lands there. That address is
internal to qemu and not directly reachable, so the template **forwards two host ports** to it on the
management NIC (`ftd0`):

  * **SSH:** `ssh -p 10022 admin@localhost` — FTD CLI
  * **FDM web UI:** `https://localhost:10443` — self-signed cert (accept the warning); give it a few
    minutes after firstboot for the web server to come up

`hostfwd` is bound `0.0.0.0`, so it's reachable from your LAN too (use the host's IP) — a lab
convenience; don't expose the host publicly. (If FTDv shuts down at the end of an unattended build,
these are only live while it's running — enable the GUI or bump `shutdown_timeout` to keep it up.)

## FMCv (Firewall Management Center)

`cisco-fmc-no-vagrant.pkr.hcl` is the FMC counterpart, now **unattended** like FTD — `boot_command`
drives the console setup (EULA, admin password, DHCP + DNS) and ends with FMC's own DB-safe
`system shutdown`, producing a configured, cleanly-stopped image. FMCv is heavy: **4 vCPU / 32 GB
RAM / 250 GB disk** (min 28 GB RAM — the packer host/VM needs ~40 GB for the build), a single virtio
management NIC. Factory login is `admin` / `Admin123`; the build changes it to **`SuperPassword123$`** (same as FTD).

```
packer build \
  -var "version=10.0.1-1" \
  -var "image_name=Cisco_Secure_FW_Mgmt_Center_Virtual_KVM-10.0.1-1.qcow2" \
  cisco-fmc-no-vagrant.pkr.hcl
```

Ports are `11xxx` (distinct from FTD's `10xxx`) so both can run together:

  * **Web UI:** `https://<host>:11443` — first boot to a ready web UI takes ~30–40m; that's where you
    accept the EULA, change the admin password, and set the network
  * **SSH:** `ssh -p 11022 admin@<host>` · **console:** VNC `<host>:5902`

Add `-var gui_disabled=false` to watch it in a QEMU window; output goes to `tmp_out_fmc/`.

**Smart-license registration is deliberately NOT part of the build.** Registering during the image
build would bake one Smart Account identity into every clone (SSM conflicts) and leave discarded
instances registered. Register each *deployed* FMC instead, via the REST API
(`POST /api/fmc_platform/v1/auth/generatetoken` → `POST /api/fmc_platform/v1/license/smartlicenses`
with `{"registrationType":"REGISTER","token":"…","force":false}`), supplying the SSM token at deploy
time. **Requires** the account to be registered (not eval mode) with export-controlled features on.

## License

MIT — see [LICENSE](LICENSE).
