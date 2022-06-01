locals {
  bastion_boot  = length(data.oci_core_boot_volume_backups.bastion_boot_backup.boot_volume_backups) != 0
  loadtest_boot = length(data.oci_core_boot_volume_backups.loadtest_boot_backup.boot_volume_backups) != 0
  dbserv0_boot  = length(data.oci_core_boot_volume_backups.dbserv_boot_backup[0].boot_volume_backups) != 0
  dbserv1_boot  = length(data.oci_core_boot_volume_backups.dbserv_boot_backup[1].boot_volume_backups) != 0
}

data "oci_core_boot_volume_backups" "bastion_boot_backup" {
  compartment_id = var.compartment_ocid
  state          = "AVAILABLE"
  display_name   = "Bastion (Boot Volume)"
}

data "oci_core_boot_volume_backups" "loadtest_boot_backup" {
  compartment_id = var.compartment_ocid
  state          = "AVAILABLE"
  display_name   = "LoadTest (Boot Volume)"
}

data "oci_core_boot_volume_backups" "dbserv_boot_backup" {
  count          = 2
  compartment_id = var.compartment_ocid
  state          = "AVAILABLE"
  display_name   = "DBServ${count.index} (Boot Volume)"
}

resource "oci_core_boot_volume" "bastion_boot" {
  count               = local.bastion_boot ? 1 : 0
  availability_domain = var.ad.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = data.oci_core_boot_volume_backups.bastion_boot_backup.boot_volume_backups[0].display_name
  vpus_per_gb         = "20"
  source_details {
    id   = data.oci_core_boot_volume_backups.bastion_boot_backup.boot_volume_backups[0].id
    type = "bootVolumeBackup"
  }
}

resource "oci_core_boot_volume" "loadtest_boot" {
  count               = local.loadtest_boot ? 1 : 0
  availability_domain = var.ad.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = data.oci_core_boot_volume_backups.loadtest_boot_backup.boot_volume_backups[0].display_name
  vpus_per_gb         = "20"
  source_details {
    id   = data.oci_core_boot_volume_backups.loadtest_boot_backup.boot_volume_backups[0].id
    type = "bootVolumeBackup"
  }
}

resource "oci_core_boot_volume" "dbserv0_boot" {
  count               = local.dbserv0_boot ? 1 : 0
  availability_domain = var.ad.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  #display_name        = data.oci_core_boot_volume_backups.dbserv_boot_backup[0].boot_volume_backups[0].display-name
  display_name = "DBServ0 (Boot Volume)"
  vpus_per_gb  = "20"
  source_details {
    id   = data.oci_core_boot_volume_backups.dbserv_boot_backup[0].boot_volume_backups[0].id
    type = "bootVolumeBackup"
  }
}

resource "oci_core_boot_volume" "dbserv1_boot" {
  count               = local.dbserv1_boot ? 1 : 0
  availability_domain = var.ad.availability_domains[1].name
  compartment_id      = var.compartment_ocid
  #display_name        = data.oci_core_boot_volume_backups.dbserv_boot_backup[1].boot_volume_backups[0].display-name
  display_name = "DBServ1 (Boot Volume)"
  vpus_per_gb  = "20"
  source_details {
    id   = data.oci_core_boot_volume_backups.dbserv_boot_backup[1].boot_volume_backups[0].id
    type = "bootVolumeBackup"
  }
}

resource "oci_core_instance" "Bastion" {
  availability_domain = var.ad.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "Bastion"
  shape               = var.bastion_shape
  state               = "RUNNING"
  source_details {
    source_id               = local.bastion_boot ? oci_core_boot_volume.bastion_boot[0].id : var.source_id
    source_type             = local.bastion_boot ? "bootVolume" : "image"
    boot_volume_size_in_gbs = local.bastion_boot ? oci_core_boot_volume.bastion_boot[0].size_in_gbs : "100"
  }
  create_vnic_details {
    subnet_id        = var.public_subnet_id
    display_name     = "primaryvnic"
    assign_public_ip = "false"
    hostname_label   = "bastion"
    #nsg_ids          = [oci_core_network_security_group.NSG_SSH_PublicVCN.id]
  }
  metadata = {
    ssh_authorized_keys = chomp(file(var.authorized_keys_path))
  }
  timeouts {
    create = "30m"
  }
}

resource "oci_core_instance" "LoadTest" {
  availability_domain = var.ad.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "LoadTest"
  shape               = var.load_shape
  state               = "RUNNING"
  source_details {
    source_id               = local.loadtest_boot ? oci_core_boot_volume.loadtest_boot[0].id : var.source_id
    source_type             = local.loadtest_boot ? "bootVolume" : "image"
    boot_volume_size_in_gbs = local.loadtest_boot ? oci_core_boot_volume.loadtest_boot[0].size_in_gbs : "100"
  }
  create_vnic_details {
    subnet_id        = var.private_subnet_id
    display_name     = "primaryvnic"
    assign_public_ip = "false"
    hostname_label   = "loadtest"
    private_ip       = var.load_ip
    #nsg_ids          = [oci_core_network_security_group.NSG_SSH_PublicVCN.id]
  }
  metadata = {
    ssh_authorized_keys = chomp(file(var.authorized_keys_path))
  }
  timeouts {
    create = "30m"
  }
}

resource "oci_core_instance" "DBServ0" {
  availability_domain = var.ad.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "DBServ0"
  shape               = var.db_shape
  state               = "RUNNING"
  source_details {
    source_id               = local.dbserv0_boot ? oci_core_boot_volume.dbserv0_boot[0].id : var.source_id
    source_type             = local.dbserv0_boot ? "bootVolume" : "image"
    boot_volume_size_in_gbs = local.dbserv0_boot ? oci_core_boot_volume.dbserv0_boot[0].size_in_gbs : "100"
  }
  create_vnic_details {
    subnet_id        = var.private_subnet_id
    display_name     = "primaryvnic"
    assign_public_ip = "false"
    hostname_label   = "dbserv0"
    private_ip       = var.db_ip[0]
    #nsg_ids          = [oci_core_network_security_group.NSG_SSH_PublicVCN.id]
  }
  metadata = {
    ssh_authorized_keys = chomp(file(var.authorized_keys_path))
  }
  timeouts {
    create = "30m"
  }
}

resource "oci_core_instance" "DBServ1" {
  availability_domain = var.ad.availability_domains[1].name
  compartment_id      = var.compartment_ocid
  display_name        = "DBServ1"
  shape               = var.db_shape
  state               = "RUNNING"
  source_details {
    source_id               = local.dbserv1_boot ? oci_core_boot_volume.dbserv1_boot[0].id : var.source_id
    source_type             = local.dbserv1_boot ? "bootVolume" : "image"
    boot_volume_size_in_gbs = local.dbserv1_boot ? oci_core_boot_volume.dbserv1_boot[0].size_in_gbs : "100"
  }
  create_vnic_details {
    subnet_id        = var.private_subnet_id
    display_name     = "primaryvnic"
    assign_public_ip = "false"
    hostname_label   = "dbserv1"
    private_ip       = var.db_ip[1]
    #nsg_ids          = [oci_core_network_security_group.NSG_SSH_PublicVCN.id]
  }
  metadata = {
    ssh_authorized_keys = chomp(file(var.authorized_keys_path))
  }
  timeouts {
    create = "30m"
  }
}

