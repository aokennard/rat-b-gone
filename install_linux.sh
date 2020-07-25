#!/bin/bash

pip3
if [[ $? -ne 0 ]]; then
    if [ -f yum ]; then yum install epel-release; yum install python-pip;
    elif [ -f pacman ]; then pacman -S python-pip;
    elif [ -f zypp ]; then zypp install python3-pip;
    elif [ -f apt-get ]; then apt-get install python3-pip;
    elif [ -f dnf ]; then dnf install python3;
    fi
fi

pip3 install -r requirements.txt

if [[ $? -ne 0 ]]; then
    echo "Pip failed to install, try manually installing it"
    exit 1
fi


if [ -z "$SM_DIR" ]; then
    echo "SM_DIR not found! searching..."
    SM_DIR=$(find / -type d -path '*/tf/addons/sourcemod' 2>/dev/null)
    if [ -z "$SM_DIR" ]; then
        echo "SM_DIR is invalid! Please set SM_DIR to your sourcemod/ path (export SM_DIR=../tf/addons/sourcemod)"
        exit 1
    fi 
    echo "SM_DIR set"
fi 

cp scripting/* $SM_DIR/scripting/

cd $SM_DIR
./scripting/spcomp autojoin.sp
mkdir -p plugins/
mv autojoin.smx plugins/