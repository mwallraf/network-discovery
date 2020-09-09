#!/bin/bash

#
# Script that should do the post-processing tasks like generating the correct output
# files in the output folder
#
# Other tasks could be to send email notifications.
#
# This is a sample file but you can use your own file by setting the
# POSTPROCESSOR env variable in your .env file
#
# This file is called from the main discover.sh file and all environment variables
# known by discover.sh should also be known here.
# If you want to call an external script then make sure to export the variables
# first.
#

# If you want to import files with different env vars this may be a good place
# to import
# . /etc/some_file_with_env_vars

# if you want to run the script directly then these are the minimal required vars
if [[ -z $SCRIPT_FOLDER ]]; then
  . ../.env
  OUTPUT_FOLDER="${SCRIPT_FOLDER}/output"
  SNMP_SYSOBJID_MAPFILE="${SCRIPT_FOLDER}/etc/sysobjectid_map.yml"
  HOSTSFILE="${SCRIPT_FOLDER}/hosts/hosts"
fi


# The following environment variables are used in our postprocessor script.
# We need to export them before they can be used in the python script

export E_HOSTSFILE=${HOSTSFILE}
export E_SNMP_SYSOBJID_MAPFILE=${SNMP_SYSOBJID_MAPFILE}
export E_IGNORE_FILE=${IGNORE_FILE}
export E_OUTPUT_FOLDER=${OUTPUT_FOLDER}


# The POSTPROCESSORDIR folder is known from discover.sh
python3 "${POSTPROCESSORDIR}/postprocessor.py"

