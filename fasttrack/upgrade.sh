#!/bin/bash
#
# upgrade.sh - Upgrade the VM's basebox with latest
#
# Author: Lord Kator <lordkator@swgemu.com>
#
# Created: Sun Aug 20 11:50:13 EDT 2017
#

if [ -z "$BASH_VERSION" ]; then
    echo "** Please use BASH to run this script **"
    exit 1
fi

OS='unknown'

main() {
    export PATH="$PATH:${VBOX_MSI_INSTALL_PATH:-${VBOX_INSTALL_PATH}}"

    pushd $(dirname "${BASH_SOURCE[0]}") > /dev/null
    local me="$(pwd -P)'/'$(basename ${BASH_SOURCE[0]})"
    popd > /dev/null

    cd "$(dirname '${me}')"

    error "NOT SUPPORTED YET DO NOT RUN THIS" 100

    # Detect OS
    case $(uname -s) in
        Darwin ) OS='osx' ;;
        *Linux* ) OS='linux' ;;
        *_NT* ) OS='win';;
        * ) echo "Not sure what OS you are on, guessing Windows"; OS='win';;
    esac

    # Is this a step?
    if [ "X$1" = "X--step" ]; then
        shift
        local step="$1"
        shift
        exec step_${step} "$@"
        error "Failed to find step: [${step}]" 127
    fi

    isHost || error "Please run this from your 'host' system (Windows, OSX, etc.)" 126

    ##########
    ## HOST ##
    ##########

    [ -d scripts/devsetup.d ] || error "You must run this from the fasttrack directory, please cd there and type: ./upgrade.sh" 10

    source ../common/global.config

    check_versions

    msg "Checking virtual machine status"
    
    local vmstatus=$(vagrant status --machine-readable|awk -F, '$3 == "state" { print $4 }')

    case $vmstatus in
        'running' )
            ;;
        'poweroff' )
            msg "Virtual Machine it powered off, will boot machine, please do not interact with it during the upgrade."
            ;;
        'not_created' )
            msg "The upgrade.sh script is designed to update an existing virtual machine to the latest base box."
            error "You can create a new virtual machine with the latest box by running: ./setup.sh" 12
            ;;
        * )
            error "Unknown virtual machine state: $vmstatus" 13
            ;;
    esac

    msg "Purging vagrant plugins"

    vagrant plugin expunge --force

    msg "Starting virtual machine"

    export ZONAMADEV_UPGRADE='yes'
    vagrant up

    local ret=$?

    if [ $ret -eq 101 ]; then
	msg "Running vagrant up again after plugin install"
	time vagrant up
	ret=$?
    fi

    if [ $ret -ne 0 ]; then
	error "** Vagrant failed to bring the VM image up, look at errors above for clues **" 14
    fi

    local sshcfg=$(mktemp /tmp/build-basebox.XXXXXX)
    trap 'rm -f "'$sshcfg'"' 0

    msg "Getting ssh configuration"
    vagrant ssh-config > $sshcfg || error "Failed to get ssh config" 15

    local cur_box=$(sed -n '/config.vm.box[ ]*=/p' ./Vagrantfile | sed -e 's/.*=[ ]*"//' -e 's/[";]*$//')
    local cur_ver=$(sed -n '/config.vm.box_version[ ]*=/p' Vagrantfile | sed -e 's/.*=[ ]*"//' -e 's/[";]*$//')

    msg "New base box: ${cur_box} (${cur_version})"

    msg "Checking virtual machine box version"
    local vm_version=$(ssh -t -F $sshcfg default "cat /.swgemudev.version") || error "Failed trying to get virtual machine version" 16

    [ -n "${vm_version}" ] || error "Failed to get virtual machine version" 17

    if [ "${vm_version}" = "${cur_ver}" ]; then
        msg "Your virtual machine is already at version ${vm_version}, no need to upgrade!"
        exit 0
    fi

    msg "Copy upgrade.sh to the virtual machine"
    scp -F $sshcfg ./upgrade.sh default:ZonamaDev/fasttrack/upgrade.sh || error "Failed to copy upgrade.sh to vm" 18

    msg "Starting preparation of the virtual machine for update (backups etc.)"
    ssh -t -F $sshcfg default "set -xe;cd ZonamaDev/fasttrack;sudo ./upgrade.sh --step vmprep 2>&1 | tee /dev/console" || error "vmprep failed: $?" 19

    # Cleanup partial downloads
    rm -fr ~/.vagrant.d/tmp/*

    # Remove prior boxes (if any)
    vagrant box list --machine-readable|sed -n '/,box-name,zonama/s/.*,//p' | while read box_name
    do
        if [ "${box_name}" != "${cur_box}" ]; then
            msg "Purging box ${box_name}"
            vagrant box remove --force "${box_name}"
        fi
    done
    
    msg "Checking disk space"

    if ! check_storage; then
        msg "WARNING: You do not have enough disk space for a recoverable upgrade!"
        echo "You can do a destructive upgrade, the files in the current vm will be backed up and then your VM will be destoryed."
        echo "A new VM will be created and your files restored to that VM."
        echo
        echo "WARNING: This means you can not fall back to the old VM if the upgrade fails!"
        echo

        if yorn "Are you worried about loosing your current VM?"; then
            msg "FREE UP MORE DISK SPACE AND TRY AGAIN"
            error "ABORTED BY USER" 101
        fi
    fi

    exit 0
}

isHost() {
    ## Check, are we running from virtual machine or the host?
    if [ -f ~/bin/zdcfg ]; then
        # Client
        return 1
    fi

    # Host
    return 0
}

check_versions() {
    msg "Checking for latest version via git"
    local old_head=$(git rev-parse HEAD)
    git stash
    git pull
    local new_head=$(git rev-parse HEAD)
    local zd_tag=$(cd ~/ZonamaDev;git describe --tag 2>> ${tmp})

    if [ "${old_head}" != "${new_head}" ]; then
        msg "Your local repo was updated to ${zd_tag}, re-running update."
        exec "${BASH_SOURCE[0]}" "$@"
        error "Failed to run ${BASH_SOURCE[0]}, try running: ./upgrade.sh" 100
    fi

    msg "Running on ZD Version ${zd_tag}"

    msg "Checking dependencies"

    ../bootstrap.sh check-versions || error "Please update your software as noted above and try again" 11
}

check_storage() {
    if [ -n "$CHECK_STORAGE_STATUS" ]; then
        return $CHECK_STORAGE_STATUS
    fi

    # Default to failure
    CHECK_STORAGE_STATUS=127

    local vmid=$(cat .vagrant/machines/default/virtualbox/id)

    [ -n "${vmid}" ] || error "Unable to determin virtualbox VM id." 17

    eval "$(VBoxManage showvminfo --machinereadable $vmid | sed -n '/vmdk/s/.*="/local vmdk="/p')"

    [ -n "${vmdk}" ] || error "Unable to find virtualbox VMDK path." 18

    local vmdk_dir=$(dirname "${vmdk}")

    return $CHECK_STORAGE_STATUS
}

step_vmprep() {
    ## THIS FUNCTION IS CALLED FROM THE HOST upgrade.sh WITH: --step vmprep
    ## WE SHOULD BE RUNNING FROM INSIDE THE VIRTUAL MACHINE!

    if isHost; then
        error "step_vmprep should run in the virtual machine!" 129
    fi
	echo 'H4sIAM3sSFoAA51QQQoAIAi7+4qB//9jmK00lCAvbtl0qrBQ6AyDnje3Ig7XBYS1LhPnd3TC85GqXkgr7iby3HhtIN0k2uNOD6vXhGoihUiWwlUri/Gq+AwZt9/r88gBAAA=' | base64 -d|gunzip
        echo ">> Stop lightdm"
        service lightdm stop
        sleep 5
        echo ">> Stop ${ZDUSER} processes"
        ps -fu ${ZDUSER} | awk 'NR > 1 && $3 == 1 { print $2 }' | xargs --no-run-if-empty -t kill
        sleep 2
        ps -fu ${ZDUSER} | awk 'NR > 1 && $3 == 1 { print $2 }' | xargs --no-run-if-empty -t kill -9
        sleep 2
        echo ">> Remaining ${ZDUSER} processes:"
        ps -fu ${ZDUSER} | sed 's/^/>> /'
        service vboxadd stop
        service mysql stop
        service syslog stop
        ${ZDHOME}/server/openresty/nginx/sbin/nginx -s stop > /dev/null 2>&1
        vbpid=$(cat /var/run/vboxadd-service.pid 2> /dev/null)
        [ -n "$vbpid" ] && kill -9 $vbpid
        sleep 5
        ps -fu ${ZDUSER}
    return 128
}

msg() {
    local hd="**"$(echo "$1"|sed 's/./*/g')"**"
    echo -e "$hd\n* $1 *\n$hd"
}

error() {
    err_msg=$1
    err_code=251
    if [ "X$2" != "X" ]; then
	err_code=$2
    fi

    msg "ERROR ON LINE ${BASH_LINENO[0]}: $err_msg ($err_code)"

    msg "If this error continues get help here: ${ZONAMADEV_URL}/issues"

    exit $err_code
}

yorn() {
    echo -n -e "$@ Y\b"
    read yorn
    case $yorn in
	[Nn]* ) return 1;;
    esac
    return 0
}

main "$@"

# vi: ft=sh sw=4 cursorline cursorcolumn
