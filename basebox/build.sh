#!/bin/bash
#
# build.sh - Build the base box from scratch
#
# Author: Lord Kator <lordkator@swgemu.com>
#
# Created: Fri Jan  1 08:00:39 EST 2016
#
# Depends: ZONAMADEV_URL

version="0.0.0"

source ../common/global.config

main() {
    if ! git diff-index --quiet HEAD . ../common; then
        echo "** WARNING: You have uncommitted changes that will NOT be reflected in the base box!"
        git status . ../common
	if yorn "\n** Do you want to abort? "; then
            echo "** ABORTED BY USER **"
            exit 0
        fi
    fi

    case $1 in
	help ) echo "$0: Choose build or package" ; exit 1 ;;
	package ) package_box ;;
	upload ) shift ; upload_box "$@" ;;
	build | * ) build_box ;;
    esac
}

build_box() {
    if [ ! -f .builder ]; then
	builder=$(cat .builder 2> /dev/null)

	while [ -z "$builder" ]
	do
	    read -p "What's your name? / Who's your daddy? " builder

	    if [[ $builder =~ .*[[:space:]].* ]]; then
		echo "** Sorry no spaces, just your base handle name please"
		builder=''
	    fi
	done

	echo "$builder" > .builder
    fi

    if [ -f package.box ]; then 
	if yorn "** Do you want to remove the old base box? "; then
	    rm -f package.box
	else
	    echo "** ABORTED BY USER **"
	    exit 0
	fi
    fi

    vagrant destroy && echo "** Destoryed old basebox VM **"

    date

    if time vagrant up; then
        :
    else
        echo "** VARGANT FAILED! RET=$? **"
        exit 1
    fi

    echo "** Ran for $SECONDS Second(s) so far."

    sleep 5

    echo "** Update vbguest extensions"
    vagrant vbguest --do install && vagrant reload

    echo "** Trying to resize to 1280x800"
    vboxmanage controlvm $(<.vagrant/machines/default/virtualbox/id) setvideomodehint 1280 800 24

    echo "** Ran for $SECONDS Second(s) so far."

    # Use instructions from README.md
    echo
    echo "*** Manual Steps ***"
    sed -e '1,/^### Manual steps/d' -e '/^###/,$d' README.md

    if yorn "Have you completed these steps?"; then
	package_box
    else
	echo "** When you're ready to package type: ./build.sh package"
	exit 0
    fi

    echo "** Ran for $SECONDS Second(s)"
}

package_box() {
    get_version

    # Make sure it's up
    echo "** Checking to make sure your guest is up..."
    if vagrant up > /dev/null 2>&1; then
	:
    else
	echo "** Failed to start the box? ret=$?"
	exit 1
    fi

    local sshcfg=$(mktemp /tmp/build-basebox.XXXXXX)
    trap 'rm -f "'$sshcfg'"' 0

    echo "** Getting ssh configuration..."
    vagrant ssh-config > $sshcfg || error "Failed to get ssh config, GET HELP!" 11

    builder=$(cat .builder 2> /dev/null)

    local branch=$(git rev-parse --abbrev-ref HEAD)

    echo "** Pulling latest greatest ${ZONAMADEV_URL} using branch ${branch}"
    if ssh -t -F $sshcfg default "sudo rm -fr ZonamaDev;git clone -b ${branch} ${ZONAMADEV_URL}"; then
	:
    else
	msg "git clone ${ZONAMADEV_URL} SEEMS TO HAVE FAILED WITH ERR=$?, fix it and after that try: ./build.sh package"
	exit 1
    fi

    echo "** Executing package prep on guest..."

    if ssh -t -F $sshcfg default "exec sudo ZDUSER=\${USER} ZonamaDev/basebox/scripts/package-prep.sh '$version' '$builder'"; then
	msg "SUCCESS!"
    else
	local st=$?

	# When the server shuts us down ssh looks like it returns 255
	if [ $st -eq 255 ]; then
            :
	else
	    # Anything else was not expected
	    msg "package-prep.sh SEEMS TO HAVE FAILED WITH ERR=$?, fix it and after that try: ./build.sh package"
	    exit 1
	fi
    fi

    # Wait for virtualbox to cleanly exit
    sleep 5

    local box_name=$(egrep 'config.vm.box[[:space:]=]' ../fasttrack/Vagrantfile | tr -d '['"'"'"]' | sed -e 's/.*=[ ]*//' -e 's/;//')

    echo "** Removing old cached boxes"

    vagrant box remove ${box_name} --all

    echo "** Ok now build the package!"

    local state='unknown'

    while [ "$state" != "poweroff" ]
    do
        state=$(vagrant status --machine-readable | awk -F',' '$3 == "state" { print $4 }')

        if [ "$state" != "poweroff" ]; then
            echo "** Box state is: ${state} must be: poweroff"
            echo
            read -p "Fix it and press <ENTER>: " _
            sleep 1
        fi
    done

    # TODO - Include a Vagrantfile with hints/metadata?
    if vagrant package; then
	:
    else
	echo "** Something went wrong!?"
	exit 1
    fi

    if [ ! -f package.box ]; then
	echo "** Something strange happened did not get a package.box file!?"
        exit 2
    fi

    local fn=package-${version}.box
    mv package.box $fn
    ls -lh "$PWD/$fn"

    upload_box "${version}" "${fn}"

    echo -e "\nNEXT STEPS:\n"

    # Show instructions from README.md
    sed -e '1,/^### Publish/d' -e '/^###/,$d' -e 's/x\.y\.z/'"${version}"'/g' -e '/```/,/```/s/^/   * /' -e '/```/d' README.md

    echo -e "\nPlease make sure you upload the box named as: ${box_name} version ${version}"

    if [ -x ~/.config/ZonamaDev/upload-box.sh ]; then
        ~/.config/ZonamaDev/upload-box.sh "${PWD}/${fn}"
    fi

    if yorn "\nAfter you upload would you like to test [$version] in the ${PWD}/../fasttrack folder?"; then
        while :
        do
            if yorn "\nDid you upload the box and set it to release yet?"; then
                if vagrant box add ${box_name} --box-version $version; then
                    break
                else
                    echo "** vagrant box add failed!"
                fi
            else
                echo "** You can't test until you upload and release the new box"
                exit 4
            fi
        done

        if yorn "\nWARNING: This will destroy your existing fasttrack box (if any) in ${PWD}/../fastrack!\n\nContinue?"; then
            set -x
            cd ../fasttrack
            if sed -i '~' 's/config.vm.box_version = ".*"/config.vm.box_version = "'${version}'"/' Vagrantfile; then
                exec ./setup.sh
            else
                echo "** Unable to edit Vagrant file, you'll have to test manually. **"
                exit 1
            fi
        else
            echo "** Test aborted, please test the box manually **"
        fi
    fi

    exit 0
}

upload_box() {
    local version=$1
    local box=$2
    local box_name=$(egrep 'config.vm.box[[:space:]=]' ../fasttrack/Vagrantfile | tr -d '['"'"'"]' | sed -e 's/.*=[ ]*//' -e 's/;//')
    local user=''
    local token=''
    
    read user token <<<$(<~/.config/ZonamaDev/vagrantup.credentials)

    if [ -z "$user" -o -z "$token" ]; then
        echo "** Please manually upload the box to vagrantup via the web UI **"
        return
    fi

    echo "** curl -s 'https://app.vagrantup.com/api/v1/box/${box_name}/version/${version}/provider/virtualbox/upload?access_token=${token}' "
    local upload_url=$(curl -s "https://app.vagrantup.com/api/v1/box/${box_name}/version/${version}/provider/virtualbox/upload?access_token=${token}" | python -c 'import sys, json; print json.load(sys.stdin)["upload_path"]')

    if [ -z "$upload_url" ]; then
        echo "Failed to find upload URL"
        return
    fi

    echo "** curl -X PUT --upload-file $box '${upload_url}'"
    curl -X PUT --upload-file $box "${upload_url}" > /dev/null
}

get_version() {
    if [ -n "$2" ]; then
	version=$2
    else
	local suggest_version=""

	# Try to guess a good version number
	local prev_version=$(grep config.vm.box_version ../fasttrack/Vagrantfile | tr -d '['"'"'"]' | sed -e 's/.*=[ ]*//' -e 's/;//')

	if [ -n "$prev_version" ]; then
	    echo -e "\nPrevious version: $prev_version\n"

	    local point=$(echo $prev_version | cut -d. -f3)

	    let "point=$point + 1"

	    suggest_version=$(echo $prev_version | sed 's/\.[0-9][0-9]*$/.'$point'/')
	fi

	local suggest=""
	
	if [ -n "$suggest_version" ]; then
	    suggest=" (ENTER for default of '$suggest_version')"
	fi

	read -p "What version do you want to use for this box$suggest? " version

	if [ -z "$version" ]; then
	    version=$suggest_version
	fi
    fi

    # TODO should we check x.y.z format?
    if yorn "\nAre you sure you want to use version [$version] for this box?"; then
	echo -e "\nNew Version: ${version}\n"
    else
	echo "** ABORTED BY USER **"
	exit 0
    fi
}

msg() {
    local hd="##"$(echo "$1"|sed 's/./#/g')"##"
    echo -e "$hd\n# $1 #\n$hd"
}

error() {
    err_msg=$1
    err_code=251
    if [ "X$2" != "X" ]; then
	err_code=$2
    fi

    msg "ERROR: $err_msg ($err_code)"

    exit $err_code
}

yorn() {
  if tty -s; then
      echo -n -e "$@ Y\b" > /dev/tty
      read yorn < /dev/tty
      case $yorn in
	[Nn]* ) return 1;;
      esac
  else
      echo "Must have a tty"
      exit 1
  fi

  return 0
}

main $@

exit 0
