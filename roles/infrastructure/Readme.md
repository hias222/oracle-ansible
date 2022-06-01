# infra

## base install ansible

ansible-galaxy collection install oracle.oci

python sdk needed
virtualenv oci
source oci/bin/activate

pip3 install oci

/Users/MFU/Library/Python/2.7/bin/pip install oci

python -c "import oci;print(oci.__version__)"

2.7
curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py
python get-pip.py --user