#!/bin/bash

. db.env

echo "oci compute image list --all --output table --compartment-id=$C"

oci compute image list --all --output table --compartment-id=$C 