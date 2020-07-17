# NETWORK-DISCOVERY

Basic network discovery script that does ping sweep, port scan and snmp polling.
The result is a single text file that can be used as input for other monitoring
systems.

The discovery is done based on pre-defined IP ranges and also manual static 
files.

An output file for ansible is created and it is copied over to Ansible
in the post-processor bash script.

When using Docker then by default the script will run every day at 17h local time. To change this login to the Docker and update the crontab.


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
docker build --tag mwallraf/network-discovery:latest .

docker run -v `pwd`/output:/opt/network-discovery/output -v `pwd`/input:/opt/network-discovery/intput -v `pwd`/env-example:/opt/network-discovery/.env --detach --name network-discovery mwallraf/network-discovery:latest
```



### Connect to the docker image

To login and connect to the docker image you can use the following command:

```
docker exec -ti network-discovery /bin/bash
```


## Environment variables

The script requires certain environment files and it will look for the following files (in order):

```
./.env
```




### Example .env file

```
# environment variables for running the network-discovery script
# this file may override other environment variables

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


## Crontab

When you use the Docker installation then the discovery script will run every day at 17h local time. You can update the crontab scheduler to run the script at different times.

Login to the docker image and then update the crontab.

```
docker exec -ti network-discovery /bin/bash

crontab -e
```
