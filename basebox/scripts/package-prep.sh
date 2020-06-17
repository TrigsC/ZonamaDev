#!/bin/bash
#
# package-prep.sh - Prepare box for packaging
#
# Author: Lord Kator <lordkator@swgemu.com>
#
# Created: Mon Dec 28 13:54:13 EST 2015
#

if [ -z "ZDUSER" ]; then
    export ZDUSER='vagrant'
fi

eval source ~${ZDUSER}/ZonamaDev/common/global.config

if [ -z "${ZDHOME}" ]; then
    echo "** Failed to parse global.config file: ZDUSER=[${ZDUSER}]"
    exit 42
fi

export PATH=${ZDHOME}/ZonamaDev/fasttrack/bin:$PATH

cd ${ZDHOME}

if [ $# -ne 2 -o -z "$1" -o -z "$2" ]; then
    echo -e "Usage: $0 #=$# {version} {builder_name}\n\t{version} - Basebox version x.y.z (e.g. 0.0.3, 0.0.9 or 1.2.3)\n\t{builder_name} - Who is building this box (e.g lordkator, scurby, darthvaderdev)"
    exit 1
fi

if [ $(id -u) -ne 0 ]; then
    echo "** Must run as root, did you sudo?"
    exit 1
fi

# Check for valid version string
if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    version="$1"
else
    echo "Invalid version string ($1), please use x.y.z where x/y/z = 1 to 3 numeric digits"
    exit 2
fi

builder_name="$2"
build_timestamp=$(date +%s)
build_datetime=$(date -u --date="@${build_timestamp}" "+%Y-%m-%dT%H:%M:%SZ")

#########################
## Verify system state ##
#########################

if zdcfg get-flag firstboot/__full_run.status; then
    :
else
    echo "** It doesn't look like firstboot completed successfully!"
    echo "** PACKAGE ABORTED **"
    exit 3
fi

if [ ! -d workspace/.metadata/.plugins/org.eclipse.ui.intro ]; then
    echo "** Please launch eclipse and make sure to select workspace, resize and exit"
    echo "** PACKAGE ABORTED **"
    exit 4
fi

###############################
## Check eclipse window size ##
###############################
eclipse_width=$(sed -n '/IDEWindow/s/.*width="\([0-9]*\)".*/\1/p' workspace/.metadata/.plugins/org.eclipse.e4.workbench/workbench.xmi)
eclipse_height=$(sed -n '/IDEWindow/s/.*height="\([0-9]*\)".*/\1/p' workspace/.metadata/.plugins/org.eclipse.e4.workbench/workbench.xmi)

if [ $eclipse_width -lt 1270 -o $eclipse_height -lt 710 ]; then
    echo "** Eclipse reports IDE window size as ${eclipse_width}x${eclipse_height}"
    echo "** Please resize to 1280x720 or more"
    echo "** DO NOT MAXIMIZE, RESIZE THE WINDOW SO THE BOTTOM PANEL IS AVAILABLE TO AVOID CONFUSING PEOPLE"
    exit 5
fi

##############################
## Check chrome window size ##
##############################
for i in work_area_bottom work_area_left work_area_right work_area_top; do eval chrome_$i=$(sed -n "s/.*\d34${i}\d34:\([0-9]*\).*/\1/p" .config/google-chrome/Default/Preferences); done

let "chrome_width=${chrome_work_area_right} - ${chrome_work_area_left}"
let "chrome_height=${chrome_work_area_bottom} - ${chrome_work_area_top}"

if [ $chrome_width -lt 1280 -o $chrome_height -lt 720 ]; then
    echo "** Chrome reports browser window size as ${chrome_width}x${chrome_height}"
    echo "** Please resize to 1280x720 or more"
    echo "** DO NOT MAXIMIZE, RESIZE THE WINDOW SO THE BOTTOM PANEL IS AVAILABLE TO AVOID CONFUSING PEOPLE"
    exit 6
fi

#------------------------------------------------------------------------------
# If we made it this far time to start cleanup for packaging...
#------------------------------------------------------------------------------

###################
## STOP SERVICES ##
###################
echo ">> Stop services"
(
    set -x
    service lightdm stop
    service vboxadd stop # Trying to avoid VM in abort state at shutdown
    service mysql stop
)

sleep 5

##########################
## KILL EVERYTHING ELSE ##
##########################
echo ">> Stop ${ZDUSER} processes"
ps -fu ${ZDUSER} | awk 'NR > 1 && $3 == 1 { print $2 }' | xargs --no-run-if-empty -t kill
sleep 2
ps -fu ${ZDUSER} | awk 'NR > 1 && $3 == 1 { print $2 }' | xargs --no-run-if-empty -t kill -9
sleep 2
echo ">> Remaining ${ZDUSER} processes:"
ps -fu ${ZDUSER} | sed 's/^/>> /'

#####################
## BRAND GRUB BOOT ##
#####################
if [ -x /usr/bin/convert ]; then
    line1="ZonamaDev Box ${version}"
    line2="Built by ${builder_name} on "$(date -u --date="@${build_timestamp}" +'%Y-%m-%d at %H:%M:%S %Z')
    echo ">> Branding bootscreen with:"
    echo ">> ** ${line1}"
    echo ">> ** ${line2}"
    srcimg=''
    for i in '/usr/share/images/desktop-base/lines-grub.png' '/usr/share/images/desktop-base/desktop-grub.png'
    do
        if [ -f "$i" ]; then
            srcimg="$i"
            break
        fi
    done
    if [ -n "$srcimg" ]; then
        convert "$srcimg" -gamma 0.6 -gravity southeast ${ZDHOME}/Pictures/logo_yellow.png'[45%]' -geometry +0+5 -composite \
            -gravity center -antialias -font Helvetica-Bold \
            -pointsize 22 -fill black -annotate +1+206 "${line1}" -annotate +2+207 "${line1}" -fill gold -annotate +0+205 "${line1}" \
            -pointsize 12 -fill black -annotate +1+226 "${line2}" -annotate +2+227 "${line2}" -fill grey -annotate +0+225 "${line2}" \
            ${ZDHOME}/Pictures/swgemu-grub.png
        if [ -f /usr/share/desktop-base/grub_background.sh ]; then
            sed -i -e "/^WALLPAPER/s@=.*@=${ZDHOME}/Pictures/swgemu-grub.png@" /usr/share/desktop-base/grub_background.sh
            sed -i -e '/GRUB_BACKGROUND/d' -e '/^GRUB_CMDLINE_LINUX_DEFAULT/s/.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
        else
            sed -i -e '$ a GRUB_BACKGROUND="'"${ZDHOME}"'/Pictures/swgemu-grub.png"' -e '/GRUB_BACKGROUND/d' -e '/^GRUB_CMDLINE_LINUX_DEFAULT/s/.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
        fi
        /usr/sbin/update-grub
    else
        echo -e "**************************************************************************************\n** WARNING: UNABLE TO FIND SOURCE GRUB BACKGROUND IMAGE, WILL NOT BRAND BOOT SCREEN **\n**************************************************************************************"
    fi
fi

#####################
## Clear run flags ##
#####################
echo ">> Clear run flags for devsetup or rc.fasttrack"
rm -fr "${ZONAMADEV_CONFIG_HOME}/flags/devsetup" "${ZONAMADEV_CONFIG_HOME}/flags/rc.fasttrack"

###############
## Clean apt ##
###############
echo ">> Cleanup apt"
apt-get --yes autoremove
apt-get --yes clean

########################
## Remove DHCP leases ##
########################
rm /var/lib/dhcp/*

###############
## Zero Swap ##
###############
echo ">> Zero swap"
readonly swapuuid=$(/sbin/blkid -o value -l -s UUID -t TYPE=swap)
readonly swappart=$(readlink -f /dev/disk/by-uuid/"$swapuuid")
/sbin/swapoff "$swappart"
dd if=/dev/zero of="$swappart" bs=1M > /dev/null 2>&1
echo ">> Make new swap"
/sbin/mkswap -U "$swapuuid" "$swappart"

###################################################
## Clean up any misc stuff in dev's user account ##
###################################################
echo ">> Cleanup user files that shouldn't be in the base box image."
(
    cd ${ZDHOME}
    mysql -e 'drop database swgemu' > /dev/null 2>&1 ;
    rm -rf .bash* .profile .inputrc .vim* .cache /var/mail/* .ssh/config .visual .gerrit_username .mysql_history .devsetup.ran .tzdata.ran .config/ZonamaDev/config
    rm -rf .xsession* .gitconfig .lesshst .ssh/id_* .subversion .cache .force_ip .iplist*
    sed -e "/ ${ZDUSER}$/p" -e 'd' -i .ssh/authorized_keys
) 2> /dev/null

# Basic files
cp -vr /etc/skel/. ${ZDHOME}

########################
## Stop all the noise ##
########################
service syslog stop
${ZDHOME}/server/openresty/nginx/sbin/nginx -s stop > /dev/null 2>&1

# Make sure VBox service really stops
vbpid=$(cat /var/run/vboxadd-service.sh 2> /dev/null)

if [ -n "$vbpid" ]; then
    echo -n ">> Waiting for vbox to stop on pid ${vbpid}"

    for i in 1 2 3 4 5
    do
        kill -0 $vbpid && break
        echo -n "."
        sleep 1
    done

    kill -9 $vbpid && echo "killed ${vbpid}"

    echo
fi

ps -fu ${ZDUSER}

##########################
## Cleanup all the logs ##
##########################
echo ">> Cleanup /var/log"
find /var/log -name \*.gz -o -name \*.[0-9] | xargs --no-run-if-empty -t rm 

rm -fr /var/tmp/* /tmp/* /etc/ssh/ssh_host*_key* /root/.viminfo /root/.bash_history /root/.lesshst /root/.bash_history /root/.ssh/* /var/log/*.gz /var/log/*.[1-9]* /var/log/*.old /var/spool/anacron/* /var/spool/mail/* /var/lib/dpkg/lock /var/cache/apt/archives/lock

find /var/log ${ZDHOME}/server/openresty/nginx/logs /etc/machine-id /var/lib/dbus/machine-id -type f | while read fn
do
    cp /dev/null "$fn"
done

mv /var/log/syslog /var/log/syslog.1 > /dev/null 2>&1

###########################################################
## Fill disk free space with zeros to aid in compression ##
###########################################################
echo ">> Fill filesystem with 0 bytes to reduce box size"
if type pv > /dev/null 2>&1; then
    pv < /dev/zero > /EMPTY
else
    dd if=/dev/zero of=/EMPTY bs=1M 2> /dev/null
fi
rm -f /EMPTY

#################################
## Save version and build info ##
#################################
echo "$version" > /.swgemudev.version
chmod 644 /.swgemudev.version
echo '{ "build_version": "'"${version}"'", "build_timestamp": '"${build_timestamp}"', "build_datetime": "'"${build_datetime}"'", "builder_name": "'"${builder_name}"'" }' | tee /.swgemudev.buildinfo.json | python -m json.tool

# Ok let these run on first boot of new fasttrack image
zdcfg clear-flag suspend_devsetup
zdcfg clear-flag suspend_fasttrack

##############################################
## Make sure box starts on ZONAMADEV_BRANCH ##
##############################################
(
    set -x
    cd ${ZDHOME}/ZonamaDev
    git checkout ${ZONAMADEV_BRANCH:-master}
    git pull
    git rev-parse --abbrev-ref HEAD
)

#####################
## Fix permissions ##
#####################
chown -R ${ZDUSER}:${ZDUSER} ${ZDHOME}

# Wait for sync to disk
echo ">> Sync disk"
sync; sync

##############
## SUCCESS! ##
##############
echo "***********************"
echo "** HALT AND POWEROFF **"
echo "***********************"

set -x

sleep 5

sync;init 0

sleep 5

# these aren't the droids you're looking for...
echo "** SHOULD NOT BE HERE! GET HELP! **"

exit 1
