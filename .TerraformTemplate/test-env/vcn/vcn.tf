resource "oci_core_virtual_network" "base_vcn" {
  cidr_block     = var.vcn_cidr
  compartment_id = var.compartment_ocid
  display_name   = var.vcn_type
  dns_label      = lower(format("%s", var.vcn_type))
}


resource "oci_core_default_security_list" "private_security_list" {
  count = var.is_private_network ? 1 : 0
  #compartment_id = var.compartment_ocid
  #vcn_id         = oci_core_virtual_network.base_vcn.id
  manage_default_resource_id = oci_core_virtual_network.base_vcn.default_security_list_id
  display_name               = "private_default_security_list"
  egress_security_rules {
    destination      = "0.0.0.0/0"
    protocol         = "6" # 6 is TCP
    destination_type = "CIDR_BLOCK"
  }
  ingress_security_rules {
    protocol = "6" # 6 is TCP
    source   = var.peer_vcn_cidr
    tcp_options {
      min = "22"
      max = "22"
    }
  }
  ingress_security_rules {
    protocol = "6" # 6 is TCP
    source   = var.vcn_cidr
    tcp_options {
      min = "22"
      max = "22"
    }
  }
  ingress_security_rules {
    protocol = "6" # 6 is TCP
    source   = var.vcn_cidr
    tcp_options {
      min = "1521"
      max = "1521"
    }
  }
}

resource "oci_core_internet_gateway" "internet_gateway_for_public" {
  # create only in public network
  count          = var.is_private_network ? 0 : 1
  compartment_id = var.compartment_ocid
  display_name   = "${var.vcn_type}_internetgateway"
  vcn_id         = oci_core_virtual_network.base_vcn.id
}

resource "oci_core_nat_gateway" "nat_gateway_for_private" {
  # create only in private network
  count          = var.is_private_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.base_vcn.id
  display_name   = "${var.vcn_type}_nat_gateway"
}

# Service Gateway for Object Storage

data "oci_core_services" "test_services" {
  filter {
    name   = "name"
    values = [".*Object.*Storage"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "service_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.base_vcn.id
  services {
    service_id = lookup(data.oci_core_services.test_services.services[0], "id")
  }
  display_name = "${var.vcn_type}_service_gateway"
}

# Local Peering Gateway
resource "oci_core_local_peering_gateway" "local_peering_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.base_vcn.id
  display_name   = "${var.vcn_type}_local_peering_gateway"
  peer_id        = var.peer_id
}

resource "oci_core_default_route_table" "default-route-table" {
  manage_default_resource_id = oci_core_virtual_network.base_vcn.default_route_table_id
  display_name               = "${var.vcn_type}-default-route-table"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = var.is_private_network ? oci_core_nat_gateway.nat_gateway_for_private[0].id : oci_core_internet_gateway.internet_gateway_for_public[0].id
  }
  route_rules {
    destination       = var.peer_vcn_cidr
    network_entity_id = oci_core_local_peering_gateway.local_peering_gateway.id
  }
  route_rules {
    destination       = lookup(data.oci_core_services.test_services.services[0], "cidr_block")
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.service_gateway.id
  }
}

resource "oci_core_subnet" "subnet" {
  compartment_id             = var.compartment_ocid
  cidr_block                 = var.vcn_cidr
  prohibit_public_ip_on_vnic = var.is_private_network
  display_name               = "${var.vcn_type}_subnet"
  dns_label                  = var.vcn_type
  vcn_id                     = oci_core_virtual_network.base_vcn.id
  security_list_ids          = null #[oci_core_virtual_network.base_vcn.default_security_list_id]
  route_table_id             = oci_core_virtual_network.base_vcn.default_route_table_id
  dhcp_options_id            = oci_core_virtual_network.base_vcn.default_dhcp_options_id
}

