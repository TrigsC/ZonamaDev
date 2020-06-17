#!/bin/bash

pushd $(dirname ${BASH_SOURCE[0]}) > /dev/null
me=$(pwd -P)'/'$(basename ${BASH_SOURCE[0]})
popd > /dev/null

cd $(dirname $me)/fasttrack

if [ -f .vagrant/machines/default/virtualbox/id ]; then
    vagrant up
    sleep 10
    exit 0
fi

./setup.sh
