provider "oci" {}

resource "oci_core_instance" "generated_oci_core_instance" {
	agent_config {
		is_management_disabled = "false"
		is_monitoring_disabled = "false"
		plugins_config {
			desired_state = "DISABLED"
			name = "Vulnerability Scanning"
		}
		plugins_config {
			desired_state = "ENABLED"
			name = "OS Management Service Agent"
		}
		plugins_config {
			desired_state = "ENABLED"
			name = "Custom Logs Monitoring"
		}
		plugins_config {
			desired_state = "ENABLED"
			name = "Compute Instance Run Command"
		}
		plugins_config {
			desired_state = "ENABLED"
			name = "Compute Instance Monitoring"
		}
		plugins_config {
			desired_state = "DISABLED"
			name = "Block Volume Management"
		}
	}
	availability_config {
		recovery_action = "RESTORE_INSTANCE"
	}
	availability_domain = "bEDy:EU-FRANKFURT-1-AD-2"
	compartment_id = "ocid1.compartment.oc1..aaaaaaaa7mtc5654de5xklhto7dyrvvcvhdz5kz4fjxbez3a2gkn4gqv7agq"
	create_vnic_details {
		assign_private_dns_record = "true"
		assign_public_ip = "false"
		subnet_id = "ocid1.subnet.oc1.eu-frankfurt-1.aaaaaaaaswchq7l3t2q2dvkxhiq62vze5pu7prtvd2r3stapsy2d43vsxska"
	}
	display_name = "l9799022"
	instance_options {
		are_legacy_imds_endpoints_disabled = "false"
	}
	metadata = {
		"ssh_authorized_keys" = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCjyUoVwevWE/AWZHutgs0qpGDi2aJ24vuaVtWwxkCw/gE5krlJN91UhdkQV4rGsINJMq6lJViMIDTnqE9JrJXPv08juNVmmH3ms7u9ZuHlr470sVsHPDUk46ttwQyoGG+ySn+MxrFqyMu/wLdG41Qb79/hdBk8EQHft7UIf49U5vdSSqsYWWLMm3zqAEAng5J/yzXU5jhrTfhBO8nKthD0c5loaIgLRsV7cpVjc/N+Qm/EIBWRzZ107xO7qn26HKbPswfGi/IDxFfzDpa2gAyb2xfhrsyxDIQwujdOi84uFUS2o4UJQa4+V+baBNnNHJXB0rxCeOAROlw6+Vlth3iH matthias.fuchs@esentri.com"
	}
	shape = "VM.Standard.E3.Flex"
	shape_config {
		baseline_ocpu_utilization = "BASELINE_1_1"
		memory_in_gbs = "64"
		ocpus = "4"
	}
	source_details {
		boot_volume_size_in_gbs = "96"
		source_id = "ocid1.image.oc1..aaaaaaaazm4ubmss5zbw2uxwlgali22wpxkm6vlkzb7yyh6j7zanq5pz5cxq"
		source_type = "image"
	}
	depends_on = [
		oci_core_app_catalog_subscription.generated_oci_core_app_catalog_subscription
	]
}

resource "oci_core_app_catalog_subscription" "generated_oci_core_app_catalog_subscription" {
	compartment_id = "ocid1.compartment.oc1..aaaaaaaa7mtc5654de5xklhto7dyrvvcvhdz5kz4fjxbez3a2gkn4gqv7agq"
	eula_link = "${oci_core_app_catalog_listing_resource_version_agreement.generated_oci_core_app_catalog_listing_resource_version_agreement.eula_link}"
	listing_id = "${oci_core_app_catalog_listing_resource_version_agreement.generated_oci_core_app_catalog_listing_resource_version_agreement.listing_id}"
	listing_resource_version = "sles-15-sp2-byos-v20210303"
	oracle_terms_of_use_link = "${oci_core_app_catalog_listing_resource_version_agreement.generated_oci_core_app_catalog_listing_resource_version_agreement.oracle_terms_of_use_link}"
	signature = "${oci_core_app_catalog_listing_resource_version_agreement.generated_oci_core_app_catalog_listing_resource_version_agreement.signature}"
	time_retrieved = "${oci_core_app_catalog_listing_resource_version_agreement.generated_oci_core_app_catalog_listing_resource_version_agreement.time_retrieved}"
}

resource "oci_core_app_catalog_listing_resource_version_agreement" "generated_oci_core_app_catalog_listing_resource_version_agreement" {
	listing_id = "ocid1.appcataloglisting.oc1..aaaaaaaa7y2u32k6q3nw3jarwfkzhhl3uuxv5t477wt26vimus2u6l34z5kq"
	listing_resource_version = "sles-15-sp2-byos-v20210303"
}
