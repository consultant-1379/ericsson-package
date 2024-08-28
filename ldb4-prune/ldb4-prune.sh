#!/bin/bash
# ********************************************************************
# Ericsson LMI                                    SCRIPT
# ********************************************************************
#
# (c) Ericsson LMI 2020 - All rights reserved.
#
# The copyright to the computer program(s) herein is the property
# of Ericsson LMI. The programs may be used and/or copied only with
# the written permission from Ericsson LMI or in accordance with the
# terms and conditions stipulated in the agreement/contract under
# which the program(s) have been supplied.
#
# ********************************************************************

# Which mount to monitor?
MOUNT="/data"
# Directory where data partitions are
PRUNING_DIRECTORY="/data/gi/ldb4/MAIN"
# Threshold trigger to start removing files
TRIGGER_THRESHOLD=95
# Threshold trigger to stop removing files
STOP_REMOVING_THRESHOLD=92
# Setting for crontab, how often to execute the script?
CRONTAB_SETTING="50 0 * * *"

ALLOWED_USER="root"
SCRIPT_DIR="/opt/ericsson/ldb4-prune/"
LOG_DIR="${SCRIPT_DIR}ldb4-prune.log"
SCRIPT_FULL_NAME="ldb4-prune.sh"
VERBOSITY=0
SCRIPT_LOG_NAME="LDB4-PRUNE"
ARG="$1"
LOG_CONFIG="/etc/logrotate.d/ldb4-prune.conf"

exec 3>&2 # logging stream (file descriptor 3) defaults to STDERR
silent_lvl=0
crt_lvl=1
err_lvl=2
wrn_lvl=3
inf_lvl=4
dbg_lvl=5

critical() { log $crt_lvl "CRITICAL [$SCRIPT_LOG_NAME] $1"; }
error() { log $err_lvl "ERROR [$SCRIPT_LOG_NAME] $1"; }
warn() { log $wrn_lvl "WARNING [$SCRIPT_LOG_NAME] $1"; }
inf() { log $inf_lvl "INFO [$SCRIPT_LOG_NAME] $1"; }
debug() { log $dbg_lvl "DEBUG [$SCRIPT_LOG_NAME] $1"; }
log() {
    datestring=`date +'%Y-%m-%d %H:%M:%S'`
    if [ $VERBOSITY -ge $1 ]; then
        echo -e "$datestring $2" | fold -w70 -s | sed '2~1s/^/  /' >&3
    else
        if [ ${ARG} == "job" ]; then
            echo -e "$datestring $2" >> ${LOG_DIR}
        else
            echo -e "$datestring $2" >&3
        fi
    fi
}

check_capacity() {
    USAGE=`df -h | grep "$MOUNT" | awk '{ print $5 }' | sed s/%//g`
    if [ ! "$?" == "0" ]
    then
        error "Mountpoint $MOUNT not found in df output."
        exit 1
    fi

    if [ -z "$USAGE" ]
    then
        error "Couldn't resolve usage information of '${MOUNT:1}' (Invalid mountpoint?)"
        exit 1
    fi

    if [ "$USAGE" -ge "$TRIGGER_THRESHOLD" ]
    then
        return 0
    else
        inf "Mount '${MOUNT:1}' at $USAGE% - within the threshold of $TRIGGER_THRESHOLD%"
        return 1
    fi
}

stop_deletion() {
    USAGE=`df -h | grep "$MOUNT" | awk '{ print $5 }' | sed s/%//g`

    if [ "$USAGE" -le "$STOP_REMOVING_THRESHOLD" ]
    then
        inf "Mount '${MOUNT:1}' at $USAGE% - within the threshold of $TRIGGER_THRESHOLD%"
        return 1
    else
        inf "Mount '${MOUNT:1}' at $USAGE%"
        return 0
    fi
}

process_file() {
    FILE="$1"
    FULL_PATH="$PRUNING_DIRECTORY/$FILE"
    rm -rf "$FULL_PATH"
    inf "Removed '$FULL_PATH' to free up space in $MOUNT"
}

setup() {
    mkdir -p ${SCRIPT_DIR}
    inf "Starting setup"
    cp $0 ${SCRIPT_DIR}
    chmod +x ${SCRIPT_DIR}
    touch ${LOG_DIR}
    chown -R ${ALLOWED_USER}:${ALLOWED_USER} ${SCRIPT_DIR}
    inf "Setting up crontab for user ${ALLOWED_USER}"
    (crontab -u ${ALLOWED_USER} -l | grep -v ${SCRIPT_DIR}${SCRIPT_FULL_NAME} ; echo "${CRONTAB_SETTING} ${SCRIPT_DIR}${SCRIPT_FULL_NAME} job") | crontab -u ${ALLOWED_USER} -
    inf "Creating logrotate configuration file - /etc/logrotate.d/ldb4-prune.conf"
    echo "${LOG_DIR} {" > ${LOG_CONFIG}
    echo "  size 10M" >> ${LOG_CONFIG}
    echo "  rotate 3" >> ${LOG_CONFIG}
    echo "  compress" >> ${LOG_CONFIG}
    echo "  copytruncate" >> ${LOG_CONFIG}
    echo "  notifempty" >> ${LOG_CONFIG}
    echo "  missingok" >> ${LOG_CONFIG}
    echo "}" >> ${LOG_CONFIG}
    inf "Setup complete"
}

uninstall() {
    inf "Removing crontab entry"
    (crontab -u ${ALLOWED_USER} -l | grep -v ${SCRIPT_DIR}${SCRIPT_FULL_NAME}) | crontab -u ${ALLOWED_USER} -
    inf "Removing logrotate configuration file"
    rm -rf ${LOG_CONFIG}
    inf "Successfully removed ${SCRIPT_LOG_NAME}"
}

main(){
    if [ $(id -u) -ne $(id -u "$ALLOWED_USER") ]; then
        echo "Log in as user $ALLOWED_USER and try again"
        exit 0
    fi
    if [ -z "$MOUNT" ] || [ ! -e "$MOUNT" ] || [ ! -d "$MOUNT" ] || [ -z "$TRIGGER_THRESHOLD" ] || [ -z "$PRUNING_DIRECTORY" ] || [ ! -e "$PRUNING_DIRECTORY" ]
    then
        exit 1
    fi

    if check_capacity
    then
        while stop_deletion
        do
            FILE_TO_DELETE=`ls -t ${PRUNING_DIRECTORY} | tail -1`

            if [ -e "$PRUNING_DIRECTORY/$FILE_TO_DELETE" ]
            then
                process_file "$FILE_TO_DELETE"
            else
                error "Mount '${MOUNT:1}' at $USAGE% exceeds the limit of $TRIGGER_THRESHOLD%, however there's no files to delete in $PRUNING_DIRECTORY!"
                exit 1
            fi
        done
    fi
}

if [[ ${ARG} == "setup" ]]; then
    if [ $(id -u) -ne $(id -u "root") ]; then
        echo "Log in as root and try again"
        exit 0
    fi
    setup
elif [[ ${ARG} == "monitor" ]] || [[ ${ARG} == "job" ]]; then
    main
elif [[ ${ARG} == "uninstall" ]]; then
    if [ $(id -u) -ne $(id -u "root") ]; then
        echo "Log in as root and try again"
        exit 0
    fi
    uninstall
else
    echo "WARNING: Please use one of the following arguments [setup/uninstall]"
    echo
    echo "$0 setup      - Install and configure the script"
    echo "$0 uninstall  - Uninstall the script and its configuration"
    echo
    echo "For example $0 setup"
    echo
fi
