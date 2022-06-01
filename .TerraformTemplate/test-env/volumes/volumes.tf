data "oci_core_volume_backups" "vol_backups" {
  compartment_id = var.compartment_ocid
  state          = "AVAILABLE"
  filter {
    name   = "display_name"
    values = ["asmdisk${var.index}.*"]
    regex  = true
  }
}

locals {
  bckp_count = length(data.oci_core_volume_backups.vol_backups.volume_backups)
}

resource "oci_core_volume" "asmdisk" {
  count = local.bckp_count == 0 ? var.num_volumes : 0
  #count               = var.new_volume_count
  display_name        = "asmdisk${var.index}.${count.index}"
  availability_domain = var.ad_name
  compartment_id      = var.compartment_ocid
  size_in_gbs         = var.size_volumes
  vpus_per_gb         = "20"
}

resource "oci_core_volume_attachment" "volume_attachment" {
  count = local.bckp_count == 0 ? var.num_volumes : 0
  #count           = var.new_volume_count
  attachment_type = "paravirtualized"
  instance_id     = var.dbserver[var.index]
  volume_id       = oci_core_volume.asmdisk[count.index].id
  #device          = "asmdisk${count.index}"
}

resource "oci_core_volume" "asmdisk_from_backup" {
  count = local.bckp_count != 0 ? local.bckp_count : 0
  #count               = var.restore_volume_count
  display_name        = "asmdisk${var.index}.${count.index}"
  availability_domain = var.ad_name
  compartment_id      = var.compartment_ocid
  size_in_gbs         = var.size_volumes
  vpus_per_gb         = "20"
  source_details {
    id   = data.oci_core_volume_backups.vol_backups.volume_backups[count.index].id
    type = "volumeBackup"
  }
}

resource "oci_core_volume_attachment" "volume_attachment_from_backup" {
  count = local.bckp_count != 0 ? local.bckp_count : 0
  #count           = var.restore_volume_count
  attachment_type = "paravirtualized"
  instance_id     = var.dbserver[var.index]
  volume_id       = oci_core_volume.asmdisk_from_backup[count.index].id
  #device          = "asmdisk${count.index}"
}

resource "oci_core_volume_group" "volume_group" {
  availability_domain = var.ad_name
  compartment_id      = var.compartment_ocid
  display_name        = "VGasmdisk${var.index}"
  source_details {
    #Required
    type = "volumeIds"
    #volume_ids = var.backups_found ? tolist(oci_core_volume.asmdisk_from_backup.*.id) : tolist(oci_core_volume.asmdisk.*.id)
    volume_ids = local.bckp_count != 0 ? tolist(oci_core_volume.asmdisk_from_backup.*.id) : tolist(oci_core_volume.asmdisk.*.id)
  }
}
