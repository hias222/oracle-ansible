# Parameters to authenticate with Oracle Cloud Infrastructure
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaacm6va45pqbiql4lenhz43csifetjupuv5opfm7bp7fblorpn7inq"
user_ocid        = "ocid1.user.oc1..aaaaaaaaj27tiiu4ycjq2omwzqnm3q5uikl6p4q4tn5vuhlhkx3hbpo2qfbq"
fingerprint      = "3f:9a:1e:7c:3d:74:9c:0a:3f:1e:0e:42:c8:ec:b4:45"
private_key_path = "/home/opc/.oci/oci_api_key.pem"

# Do all work in this compartment
compartment_ocid = "###IT_SHOULD_BE_OBVIOUS_THIS_MUST_BE_REPLACED_BY_THE_REAL_COMPARTMENT_OCID####"

# Leave empty if your private key does not have a password
private_key_password = ""

# See https://docs.oracle.com/pls/topic/lookup?ctx=cloud&id=oci_general_regions
home_region = "eu-frankfurt-1"
region      = "eu-frankfurt-1"

# CIDR for public and private VCNs
public_vcn_cidr  = "192.168.4.0/24"
private_vcn_cidr = "10.0.10.0/24"

# The Shapes
bastion_shape = "VM.Standard2.1"
load_shape    = "VM.DenseIO2.8"
db_shape      = "VM.DenseIO2.16"

# ASM Disks
# size is in GB
num_volumes  = 3
size_volumes = 128

# ssh
authorized_keys_path = "./assets/ba_public_keys.pub"
