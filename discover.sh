#!/bin/bash -e
#
# Generic Shell Script Skeleton.
# Copyright (c) {{ YEAR }} - {{ AUTHOR }} <{{ AUTHOR_EMAIL }}>
#
# Built with shell-script-skeleton v0.0.3 <http://github.com/z017/shell-script-skeleton>

# Import common utilities
source "$(dirname "${BASH_SOURCE[0]}")/functions/common.sh"

# Import python env
# source "$(dirname "${BASH_SOURCE[0]}")/venv/bin/activate"

# Import OBE global env variables if exists
if [[ -f "/etc/OBE/env-bash" ]]; then
  source "/etc/OBE/env-bash"
fi

# Import local config if it exists
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/.env" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/.env"
fi

readonly SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")

#######################################
# SCRIPT CONSTANTS & VARIABLES
#######################################

# Script version
readonly VERSION=0.0.2

# List of required tools, example: REQUIRED_TOOLS=(git ssh)
readonly REQUIRED_TOOLS=()

# Long Options. To expect an argument for an option, just place a : (colon)
# after the proper option flag.
readonly LONG_OPTS=(help version force no-snmp)

# Short Options. To expect an argument for an option, just place a : (colon)
# after the proper option flag.
readonly SHORT_OPTS=hvd

# Script name
readonly SCRIPT_NAME=${0##*/}

# Postprocessor script, to generate reports
readonly POSTPROCESSORDIR="$SCRIPTDIR/etc"

# Define temp folders and other locations
readonly HOSTSDIR="$SCRIPTDIR/hosts"
readonly HOSTSFILE="$HOSTSDIR/hosts"

readonly DISCOVERYDIR="$SCRIPTDIR/hosts/_discovery"
readonly PINGSWEEPDIR="$DISCOVERYDIR/ping"
readonly PINGSWEEPFILE="$DISCOVERYDIR/pingsweep.txt"
readonly SNMPFILE="$DISCOVERYDIR/snmp.txt"


# Location to FPING, SED, SNMPGET
if [[ -z ${FPING} ]]; then
  readonly FPING=$(which fping)
fi

if [[ -z ${SED} ]]; then
  readonly SED=$(which sed)
fi

if [[ -z ${SNMPGET} ]]; then
  readonly SNMPGET=$(which snmpget)
fi

if [[ -z ${RUNPOSTPROCESSOR} ]]; then
  readonly RUNPOSTPROCESSOR=1
fi


# Force flag
declare FORCE=false
declare SHOWHELP=true



#######################################
# SCRIPT CONFIGURATION CONSTANTS
#######################################

# Subnets for which discovery should run
# example: ("10.8.90.0/23" "10.8.92.0/24")
if [[ -z ${DISCOVER_SUBNETS} ]]; then
  readonly DISCOVER_SUBNETS=()
fi

# Snmp community strings to use
if [[ -z ${SNMP_COMMUNITIES} ]]; then
  readonly SNMP_COMMUNITIES=("public")
fi

# Folder that contains file with static entries
if [[ -z ${STATIC_INPUT_FOLDER} ]]; then
  readonly STATIC_INPUT_FOLDER="$SCRIPTDIR/input"
fi

# Folder that is used to store output files
if [[ -z ${OUTPUT_FOLDER} ]]; then
  readonly OUTPUT_FOLDER="$SCRIPTDIR/output"
fi

# FORK environment variable
if [[ -z ${FORKS} ]]; then
  readonly FORKS=5
fi

# link to the sysobj id mapping, used in postprocessor
if [[ -z ${IGNORE_FILE} ]]; then
  readonly IGNORE_FILE="$STATIC_INPUT_FOLDER/network-discovery.ignore"
fi

# link to the sysobj id mapping, used in postprocessor
if [[ -z ${SNMP_SYSOBJID_MAPFILE} ]]; then
  readonly SNMP_SYSOBJID_MAPFILE="$SCRIPTDIR/etc/sysobjectid_map.yml"
fi

# the postprocessor script should be a bash script with execute permissions
if [[ -z ${POSTPROCESSOR} ]]; then
  readonly POSTPROCESSOR="$POSTPROCESSORDIR/run_postprocessor.sh"
fi

declare NOSNMP=


#echo ${DISCOVER_SUBNETS[@]}



#######################################
# help command
#######################################
function help_command() {
  cat <<END;

ABOUT:
  Discover networks based on predefined subnets and generate a single output
  file which can be used as source for other management tools.

USAGE:
  $SCRIPT_NAME [options] <command>

OPTIONS:
  --help, -h              Alias help command
  --version, -v           Alias version command
  --no-snmp               Do not do SNMP scanning (default=yes)
  --force                 Don't ask for confirmation
  --                      Denotes the end of the options.  Arguments after this
                          will be handled as parameters even if they start with
                          a '-'.

COMMANDS:
  discover                Start the discovery
  help                    Display detailed help
  version                 Print version information.

END
  exit 1
}

#######################################
# version command
#######################################
function version_command() {
  echo "$SCRIPT_NAME version $VERSION"
}

#######################################
# default command
#######################################
function default_command() {
  # set default command here
  if [ ${SHOWHELP} ]; then
    help_command
  fi
}


function start_discovery() {

  SHOWHELP=
  echo "--- Start network discovery ---"
  SECONDS=0
  create_dirs
  pingsweep

  if [ ! ${NOSNMP} ]; then
    snmpscan
  fi

  cleanup
  if [ ${RUNPOSTPROCESSOR} == 1 ]; then
    start_postprocessor
  fi
  echo "--- The script has taken $SECONDS seconds to finish ---"
}


####################################
# Start the postprocessor and store
# Environment variables are passed to the postprocessor bash script
# But in the postprocessor script you still need to export the
# required variables if you want to use them in external python
# scripts for example.
# The purpose is that the postprocessor script will generate
# results in the output folder
####################################
function start_postprocessor()
{
  echo "starting postprocessor: ${POSTPROCESSOR}"
  . $POSTPROCESSOR
}

#######################################
# create temp folders
#######################################
function create_dirs()
{
    # remove the existing temp folders:
    rm -rf "$DISCOVERYDIR"

    # create temp folders
    mkdir -p "$HOSTSDIR"
    mkdir -p "$DISCOVERYDIR"
    mkdir -p "$PINGSWEEPDIR"
}

#######################################
# generate discovery hosts file and cleanup
#######################################
function cleanup()
{

    echo "Save hosts file"

    echo "MGMTIP:HOSTNAME:COMMUNITY:SYSOBJID:SYSCONTACT:SYSDESCR" > $HOSTSFILE

    if [ ! ${NOSNMP} ]; then

      if [[ -d ${PINGSWEEPDIR} ]]; then
        cat ${PINGSWEEPDIR}/*.snmp >> $HOSTSFILE
      fi

    else

      eval "$SED -i -e 's/\(.*\)/\1:::::/g' $PINGSWEEPFILE"
      cat $PINGSWEEPFILE >> $HOSTSFILE

    fi

    rm -rf "$DISCOVERYDIR"
}



#######################################
# include hosts from static files
#######################################
function include_static_files()
{
    # include all *txt files in the static input folder
    if [[ -d ${STATIC_INPUT_FOLDER} ]]; then
      for F in ${STATIC_INPUT_FOLDER}/*.txt
      do
        echo "  > sweep input file: ${F}"
        CMD="$FPING -A -c 1 -g -f ${F} >> $PINGSWEEPFILE  2> /dev/null"
        eval $CMD
      done
    fi
}



#######################################
# pingsweep function
#######################################
function pingsweep()
{
    rm -rf $PINGSWEEPFILE

    echo "Start pingsweep"

    # do a ping sweep and save the result in _reachability
    for i in ${DISCOVER_SUBNETS[@]}; do
        echo "  > sweep range: $i"
        CMD="$FPING -A -c 1 -g $i >> ${PINGSWEEPFILE}  2> /dev/null"
        eval $CMD
    done

    include_static_files

    # remove empty lines and everything behind a space
    CMD="$SED -i -e 's/ .*//g' ${PINGSWEEPFILE}"
    eval $CMD

    # remove duplicates
    sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n -o ${PINGSWEEPFILE} ${PINGSWEEPFILE}


    # split the sweepfile in equal chunks, base on FORKS
    total_lines=`wc -l $PINGSWEEPFILE | cut -d' ' -f1`
    ((lines_per_part=(total_lines + $FORKS - 1) / $FORKS))
    split -l ${lines_per_part} ${PINGSWEEPFILE} ${PINGSWEEPDIR}/pingsweep.

}



#######################################
# portscan function
# TODO: not used for now
#######################################
#function portscan()
#{
#    # do a portscan and check if a host has ping or ssh enabled
#    # this is only done on the reachable hosts
#    rexHostname="[^/]*$"
#    for F in $HOSTSDIR/_reachability/*.txt
#    do
#        HN=`echo $F | grep -oP "$rexHostname"`
#        CMD="sudo nmap -p22-23 -n -iL $F -oG $HOSTSDIR/_protocol/$HN"
#        #echo "$CMD"
#        eval $CMD
#    done
#}


#######################################
# snmpscan function
#######################################

function snmp_child()
{
    # runs an SNMP scan on a single hosts file f
    # this function can be started in parallel

    SWEEPFILE=$1

    # do an SNMP scan on sysDescr
    # this is only done on the hosts that were found by the pingsweep
    rexHostname="[^/]*$"
    timeout=1
    retries=1

    echo "Start SNMP scan on file $SWEEPFILE"

    while IFS='' read -r line || [[ -n "$line" ]]; do
        POLL_SUCCESS=
        for community in "${SNMP_COMMUNITIES[@]}"
        do
            echo "  > scan $line"
            CMD="$SNMPGET -v2c -c $community -OaenUqv -t$timeout -r$retries -Lo $line sysObjectID.0"
            snmp=$($CMD)
            #echo "CMD: $CMD"
            #echo "snmp: $snmp"
            if [[ $snmp =~ 1\.3\.6\.1\.4\.1\. ]]; then
                sysname=$(snmpget -v2c -c $community -OaenUqv -t$timeout -r$retries -Lo $line sysName.0)
                sysdescr=$(snmpget -v2c -c $community -OaenUqv -t$timeout -r$retries -Lo $line sysDescr.0 | head -n 1 | $SED -e 's/:/./g')
                syscontact=$(snmpget -v2c -c $community -OaenUqv -t$timeout -r$retries -Lo $line sysContact.0 | head -n 1 | $SED -e 's/:/./g')
                echo "$line:$sysname:$community:$snmp:${syscontact//$'\t\r\n'}:${sysdescr//$'\t\r\n']}" >> "$SWEEPFILE.snmp"
                #echo "$line:$sysname:$community:$snmp:$syscontact:$sysdescr"
                POLL_SUCCESS=1
                break
            fi
        done
        if [ ! ${POLL_SUCCESS} ]; then
          echo "SNMP failed for $line"
          echo "$line:::::" >> "${SWEEPFILE}.snmp"
        fi
    done < "$SWEEPFILE"
}

function snmpscan()
{
    # run snmp scan on each sweepfile

    if [[ -d ${PINGSWEEPDIR} ]]; then
      echo "Start SNMP scan"
      for F in ${PINGSWEEPDIR}/pingsweep.*
      do
        snmp_child $F &
      done

    fi

    wait
}




#######################################
#
# MAIN
#
#######################################
function main() {
  # Required tools
  required $REQUIRED_TOOLS

  # Parse options
  while [[ $# -ge $OPTIND ]] && eval opt=\${$OPTIND} || break
        [[ $opt == -- ]] && shift && break
        if [[ $opt == --?* ]]; then
          opt=${opt#--}; shift

          # Argument to option ?
          OPTARG=;local has_arg=0
          [[ $opt == *=* ]] && OPTARG=${opt#*=} && opt=${opt%=$OPTARG} && has_arg=1

          # Check if known option and if it has an argument if it must:
          local state=0
          for option in "${LONG_OPTS[@]}"; do
            [[ "$option" == "$opt" ]] && state=1 && break
            [[ "${option%:}" == "$opt" ]] && state=2 && break
          done
          # Param not found
          [[ $state = 0 ]] && OPTARG=$opt && opt='?'
          # Param with no args, has args
          [[ $state = 1 && $has_arg = 1 ]] && OPTARG=$opt && opt=::
          # Param with args, has no args
          if [[ $state = 2 && $has_arg = 0 ]]; then
            [[ $# -ge $OPTIND ]] && eval OPTARG=\${$OPTIND} && shift || { OPTARG=$opt; opt=:; }
          fi

          # for the while
          true
        else
          getopts ":$SHORT_OPTS" opt
        fi
  do
    case "$opt" in
      # List of options
      v|version)    version_command; exit 0; ;;
      h|help)       help_command ;;
      no-snmp)      NOSNMP=true ;;
      force)        FORCE=true ;;
      # Errors
      ::)   err "Unexpected argument to option '$OPTARG'"; exit 2; ;;
      :)    err "Missing argument to option '$OPTARG'"; exit 2; ;;
      \?)   err "Unknown option '$OPTARG'"; exit 2; ;;
      *)    err "Internal script error, unmatched option '$opt'"; exit 2; ;;
    esac
  done
  readonly FORCE
  readonly NOSNMP
  shift $((OPTIND-1))

  # No more arguments -> call default command
  [[ -z "$1" ]] && default_command

  # Set command and arguments
  command="$1" && shift
  args="$@"

  # Execute the command
  case "$command" in
    # help
    help)     help_command ;;

    # version
    version)  version_command ;;

    # start the discovery
    discover) start_discovery ;;

    # Unknown command
    *)  err "Unknown command '$command'"; exit 2; ;;
  esac
}
#######################################
# Run the script
#######################################
main "$@"

