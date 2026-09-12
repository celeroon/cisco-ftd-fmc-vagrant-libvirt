packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "version" {
  type    = string
  default = "unknown"
}

variable "gui_disabled" {
  type    = bool
  default = true # headless by default (VNC only). Enable the QEMU GUI window with -var gui_disabled=false
}

variable "boot_time" {
  type    = string
  default = "10m" # FTDv takes ~10m to reach the login prompt before boot_command can type
}

variable "boot_key_interval" {
  type    = string
  default = "50ms"
}

variable "shutdown_timeout" {
  type    = string
  default = "45m" # FTDv first boot is slow (~15-30m to the setup prompt) + your hands-on time
}

variable "cpus" {
  type    = number
  default = 4 # FTDv minimum is 4 vCPU / 8 GB RAM
}

variable "memory" {
  type    = number
  default = 8192
}

variable "disk_cache" {
  type = string
  # firstboot is write-heavy; "none" (O_DIRECT) is slow on nested/contended storage.
  # "unsafe" caches writes in host RAM and skips guest flushes — fine for a throwaway
  # build image (a host crash mid-build just means rebuild); use "writeback" to keep flushes.
  default = "unsafe"
}

variable "image_name" {
  type    = string
  default = "ftdv"
}

variable "image_path" {
  default = "/var/lib/libvirt/images"
}

variable "out_dir" {
  type    = string
  default = "tmp_out"
}

variable "vnc_port" {
  type    = number
  default = 5901
}

source "qemu" "cisco-ftd" {
  accelerator       = "kvm"
  cpus              = var.cpus
  memory            = var.memory
  skip_resize_disk  = true
  skip_compaction   = true
  disk_image        = true
  use_backing_file  = false
  disk_interface    = "virtio"
  disk_cache        = var.disk_cache
  format            = "qcow2"
  net_device        = "virtio-net"
  iso_checksum      = "none"
  iso_url           = "${var.image_path}/${var.image_name}"
  boot_wait         = "${var.boot_time}"
  boot_key_interval = "${var.boot_key_interval}"
  headless          = "${var.gui_disabled}"
  communicator      = "none"
  vm_name           = "cisco-ftd-${var.version}.qcow2"
  output_directory  = "${var.out_dir}"
  shutdown_timeout  = "${var.shutdown_timeout}"

  qemuargs = [
    ["-cpu", "host"],
    ["-netdev", "user,id=ftd0,hostfwd=tcp:0.0.0.0:10022-:22,hostfwd=tcp:0.0.0.0:10443-:443"],
    ["-device", "virtio-net-pci,netdev=ftd0"],
    ["-netdev", "user,id=ftd1"],
    ["-device", "virtio-net-pci,netdev=ftd1"],
    ["-netdev", "user,id=ftd2"],
    ["-device", "virtio-net-pci,netdev=ftd2"],
    ["-netdev", "user,id=ftd3"],
    ["-device", "virtio-net-pci,netdev=ftd3"]
  ]

  boot_command = [
    "admin<enter><wait5>",
    "Admin123<enter><wait10>",
    "<enter><wait5>",
    "YES<enter><wait5>",
    "SuperPassword123$<enter><wait5>",
    "SuperPassword123$<enter><wait10>",
    "<enter><wait5>",
    "<enter><wait5>",
    "dhcp<enter><wait1m>",
    "<enter><wait1m>",
    "shutdown<enter><wait10>",
    "YES<enter>"
  ]
}

build {
  sources = ["source.qemu.cisco-ftd"]
}
