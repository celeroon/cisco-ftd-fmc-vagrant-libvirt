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
  default = "40m" # FMCv takes ~40m to reach the console login prompt before boot_command can type
}

variable "boot_key_interval" {
  type    = string
  default = "50ms"
}

variable "shutdown_timeout" {
  type    = string
  default = "90m" # FMCv first boot to a ready web UI is slow (~30-40m) + your setup/verify time
}

variable "cpus" {
  type    = number
  default = 4 # FMCv: 4 vCPU / 32 GB RAM / 250 GB disk (min 28 GB RAM)
}

variable "memory" {
  type    = number
  default = 32768
}

variable "image_name" {
  type    = string
  default = "fmcv"
}

variable "image_path" {
  default = "/var/lib/libvirt/images"
}

variable "out_dir" {
  type    = string
  default = "tmp_out_fmc"
}

variable "vnc_port" {
  type    = number
  default = 5902
}

source "qemu" "cisco-fmc" {
  accelerator       = "kvm"
  cpus              = var.cpus
  memory            = var.memory
  skip_resize_disk  = true
  skip_compaction   = true
  disk_image        = true
  use_backing_file  = false
  disk_interface    = "virtio"
  disk_cache        = "none"
  format            = "qcow2"
  net_device        = "virtio-net"
  iso_checksum      = "none"
  iso_url           = "${var.image_path}/${var.image_name}"
  boot_wait         = "${var.boot_time}"
  boot_key_interval = "${var.boot_key_interval}"
  headless          = "${var.gui_disabled}"
  communicator      = "none"
  vm_name           = "cisco-fmc-${var.version}.qcow2"
  output_directory  = "${var.out_dir}"
  shutdown_timeout  = "${var.shutdown_timeout}"

  qemuargs = [
    ["-cpu", "host"],
    ["-netdev", "user,id=fmc0,hostfwd=tcp:0.0.0.0:11022-:22,hostfwd=tcp:0.0.0.0:11443-:443"],
    ["-device", "virtio-net-pci,netdev=fmc0"]
  ]

  boot_command = [
    "admin<enter><wait5>",
    "Admin123<enter><wait10>",
    "<enter><wait5>",
    "YES<enter><wait10>",
    "SuperPassword123$<enter><wait5>",
    "SuperPassword123$<enter><wait10>",
    "<enter><wait5>",
    "dhcp<enter><wait5>",
    "8.8.8.8<enter><wait5>",
    "<enter><wait5>",
    "y<enter><wait1m>",
    "system shutdown<enter><wait5>",
    "yes<enter>"
  ]
}

build {
  sources = ["source.qemu.cisco-fmc"]
}
