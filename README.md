# NETWORK-DISCOVERY

Basic network discovery script that does ping sweep, port scan and snmp polling.
The result is a single text file that can be used as input for other monitoring
systems.

The discovery is done based on pre-defined IP ranges and also manual static 
files.

An output file for ansible is created and it is copied over to Ansible
in the post-processor bash script.


## Installation

The recommended installation is by using Docker.

## Environment variables

    * DISCOVER_SUBNETS: list of CIDR subnets that should be discovered
    * STATIC_INPUT_FOLDER: folder where the static input files can be found
    * IGNORE_FILE: file that contains ip addresses that should be ignored
    * FORKS: number of simulataneous snmp polls
    * OUTPUT_FOLDER: folder where output reports are stored
    * RUNPOSTPROCESSOR: trigger if the postprocessor script should run
    * POSTPROCESSOR: file that is used as postprocessor, this should be a python script
    * SNMP_COMMUNITIES: list of snmp communities that should be tried
    * SNMP_SYSOBJID_MAPFILE: file that contains the snmp sysobjid mapping to device types


## Docker

It's possible to run the network-discover script in a Docker container. If needed update the ```env-example``` file with your customize environment variables, create a local ```input``` + ```output``` folder and map these to the correct locations in the docker run command.

Build + run the docker container:

```
docker build --tag mwallraf/network-discovery:1.0 .

docker run -v `pwd`/output:/opt/network-discovery/output -v `pwd`/input:/opt/network-discovery/intput -v `pwd`/env-example:/opt/network-discovery/.env --detach --name network-discovery mwallraf/network-discovery:1.0
```



### Connect to the docker image

To login and connect to the docker image you can use the following command:

```
docker exec -ti network-discovery /bin/bash
```


## Environment variables

The script requires certain environment files and it will look for the following files (in order):

```
/etc/OBE/env-bash
./.env
```


### Example /etc/OBE/env-bash file

```
############################################################
# BASH environment file that contains generic information
# that can be used as input by different scripts
#
# Scripts using this file:
#   - network-discovery
#
# LAST UPDATE BY: Maarten Wallraf
# LAST UPDATED: 2020-07-15
#
############################################################

# LEGACY INFO:
#    10.155.x.x was used for ERS/ESU but is removed

CES_MGMT_RANGES=("10.8.90.0/23" "10.8.92.0/24" "10.8.20.0/23" "10.8.22.0/24" "10.8.15.0/24" "10.8.88.0/24" "10.8.19.0/24" "10.8.66.0/24" "10.8.53.0/24" "10.8.51.0/24" "10.8.82.0/24" "10.8.27.0/24")
CES_MGMT_RANGES_TTN=("10.8.25.0/24")
TROPS_DCN=("10.0.32.0/23" "10.0.96.0/23" "10.8.254.0/24" "10.8.253.0/24" "10.8.252.0/24" "10.8.2.0/24" "10.8.9.0/24")
DCN=("10.11.222.0/23" "10.11.16.0/20" "10.11.32.0/20")
DCN_LOOPBACK=("10.0.62.0/24" "10.0.126.0/24")
PBXPLUG=("94.105.56.0/21")
L2_LBB_CPE=("10.94.32.0/20")
INTERNET_P2P=("94.104.128.0/17")
IPVPN_LOOPBACK=("94.105.0.0/18")
CORE_LOOPBACK=("195.242.172.0/24")

DISCOVER_SUBNETS=(${CES_MGMT_RANGES[@]} ${TROPS_DCN[@]} ${CES_MGMT_RANGES_TTN[@]} ${DCN[@]} ${DCN_LOOPBACK[@]} ${L2_LBB_CPE[@]} ${INTERNET_P2P[@]} ${IPVPN_LOOPBACK[@]} ${CORE_LOOPBACK[@]})
#DISCOVER_SUBNETS=("10.0.32.0/24")
SNMP_COMMUNITIES=("5pr1t5" "public" "y0upvth3k" "53h3lth0nl13")
#SNMP_COMMUNITIES=("public")
```



### Example .env file

```
# environment variables for running the network-discovery script
# this file may override other environment variables configured in
# /etc/OBE/env-bash

SCRIPT_FOLDER="/opt/network-discovery"

STATIC_INPUT_FOLDER="${SCRIPT_FOLDER}/input"
IGNORE_FILE=${STATIC_INPUT_FOLDER}/network-discovery.ignore
FORKS=15
OUTPUT_FOLDER="${SCRIPT_FOLDER}/output"

# BY DEFAULT THE POSTPROCESSOR WILL RUN
RUNPOSTPROCESSOR=0

# YOU CAN OVERRIDE HERE
# DISCOVER_SUBNETS=("192.168.84.0/24")
```


## Ignore certain IP addresses

If you specifically want to ignore certain IP addresses to be discovered then you can add them to ```/opt/network-discovery/input/static.ignore``` file.

### Example static.ignore file

```
10.8.90.251 # server
94.104.255.50 # ANT-IPSEC-01 loopback
94.104.255.51 # NOS-IPSEC-01 loopback
```



