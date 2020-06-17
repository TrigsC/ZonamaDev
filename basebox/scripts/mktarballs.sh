#!/bin/bash
#
# mktarballs.sh - Make the tar balls needed to save manual setup time of the basebox configuration
# 
# Author: Lord Kator <lordkator@swgemu.com>
#
# Created: Mon Dec 26 08:04:55 EST 2016
#
# NOTE: note all files should be placed here, only things changes when you manually configure things
#
# Example to detect config changes, from a fresh basebox after the scripts have run you can do:
#
# vagrant ssh
# touch /tmp/stamp
# << do manual config on the gui >>
# find . -newer /tmp/stamp -depth
# <control-d>
#
# Edit mktarballs.sh and add directories as needed or singular files
#
# Then from the host run: ./mktarballs.sh
#
# Try to choose the core directory where the change happened and make sure you use absolute paths
# from the $HOME directory.
#
# On basebox firstboot all tarballs are extracted to ZDHOME by basebox/scripts/firstboot.d/10tarballs
#

main() {
    # default-config.tar.gz - Capture most of the things we care about
    mktarball default-config.tar.gz \
        .config/google-chrome/ \
        .config/xfce4/ \
        .config/dconf/user \
        .gnome/apps/ \
        .mozilla/firefox \
        Pictures/3073-starwars-galaxies-002-ilhrq.jpg \
        Pictures/logo_yellow.png

    # Eclipse config changes a lot from version to version, not safe to have it in tar file -- Karl 07/02/2017
    # eclipse/configuration/config.ini \
    # workspace/.metadata/.plugins/org.eclipse.e4.workbench/workbench.xmi

    echo "**"
    echo "** Don't forget to add the files to git and push them before testing!"
    echo "**"
    echo "** git add -A ${TARBALLDIR}"
    echo "** git commit -m 'Updated mktarballs.sh'"
    echo "** git push"
    echo "**"
    exit 0
}

mktarball() {
    local tarball="${TARBALLDIR}/$1"
    local newtarball="${tarball}~new~"
    local errfile="${newtarball}~errors~"
    local oldtarball="${tarball}~"
    shift

    echo "** Creating ${tarball} with files: $@"

    ssh -F "${SSHCONFIG}" default '(set -x;cd "'"${ZDHOME}"'";tar czf - '"$@"')' > "${newtarball}" 2> >(tee "${errfile}" >&2)

    echo "**"

    local errcount=$(egrep '^tar: ' "${errfile}"|wc -l)

    if [ "${errcount}" -gt 0 ]; then
        echo "** FAILED **"
        echo "** Resolve these errors and retry:"
        sed -n -e '/^\+ /s/^/** /p' -e '/^tar: /s/^/** /p' "${errfile}"
        echo "**"
        rm -f "${newtarball}" "${errfile}"
        exit 13
    fi

    local count=$(tar tf "${newtarball}"|wc -l)

    if [ "${count}" -le 0 ]; then
        echo "** Failed to create tarball, look above for errors."
        rm -f "${newtarball}" "${errfile}"
        exit 11
    fi

    echo "** SUCCESS, SAVED" ${count} "FILE(S) **"

    if [ -f "${tarball}" -a ! -f "${oldtarball}" ]; then
        echo "Saved old tarball to ${oldtarball}"
        mv "${tarball}" "${oldtarball}"
    fi

    mv "${newtarball}" "${tarball}"
    rm -f "${errfile}"
}

tarballprep() {
    # Get script's full pathname
    pushd $(dirname ${BASH_SOURCE[0]}) > /dev/null
    export ME=$(pwd -P)'/'$(basename ${BASH_SOURCE[0]})
    popd > /dev/null

    # Hunt for global.config
    dir=$(dirname $ME)
    for i in "$HOME" "${dir}" "${dir}/.." "${dir}/../.." "${dir}/../../.."
    do
        cfg="${i}/ZonamaDev/common/global.config"

        if [ -f "${cfg}" ]; then
            export ZDCFGPATH="${cfg}"
            break
        fi
    done

    if [ -z "${ZDCFGPATH}" -o ! -f "${ZDCFGPATH}" ]; then
        echo "** ERROR: Can not find global.config, GET HELP!"
        exit 252
    fi

    echo "** Using config ${ZDCFGPATH}"
    source "${ZDCFGPATH}"

    if [ "${USER}" == "${ZDUSER}" ]; then
        echo "** Run this script from the host machine, it will ssh in and run as needed"
        exit 1
    fi

    TARBALLDIR=$(dirname $ME)'/../tarballs/'
    TARBALLDIR=$(cd "${TARBALLDIR}";/bin/pwd -P)

    SSHCONFIG=$(mktemp)
    trap 'rm -f "${SSHCONFIG}"' 0 1 2 15

    cp /dev/null "${SSHCONFIG}"

    echo -n '** Getting ssh config...'
    (cd $(dirname "${ZDCFGPATH}")"/../basebox";vagrant ssh-config > "${SSHCONFIG}")
    echo " **"

    if [ ! -s "${SSHCONFIG}" ]; then
        echo "** Failed to get ssh config from vagrant?"
        exit 12
    fi
}

tarballprep

main

exit 0
