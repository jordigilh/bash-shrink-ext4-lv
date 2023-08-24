#!/bin/bash

FSTAB_FILE='/etc/fstab'
SHRINK_TAG='x-systemd.shrinkfs'

function read_fstab() {
    while IFS= read -r line; do
        case $line in
        \#* )
        ;;
        "" )
        ;;
        UUID=*|/dev/* )
        if [[ "$line" == "$device_name "* ]]; then
            echo "$line" 
            break
        fi
        ;;
        esac
    done < $FSTAB_FILE
}


function get_device_name() {
    if [[ "$1" == "UUID="* ]]; then
        parse_uuid "$1"
    else
        cut -d " " -f 1 <<< "$1"
    fi      
} 

function get_tag_value_in_bytes() {
    IFS=, read -ra options <<< "$1"
    for opt in "${options[@]}"; do
        if [[ "$opt" == "$SHRINK_TAG="* ]]; then
            /usr/bin/numfmt  --from iec "${opt#*=}" 
            break
        fi
    done
}

function parse_tag() {
    if [[ "$1" == *"$SHRINK_TAG="* ]]; then 
        get_tag_value_in_bytes "$1"
    fi
}

function is_device_mounted() {
    /usr/bin/findmnt --source "$1" 1>&2>/dev/null
    status=$?
    if [[  status -eq 0 ]]; then
        echo "Device $1 is mounted"
        exit 1
    fi
}

function get_current_volume_size() {
    val=$(/usr/bin/lsblk -b "$1" -o SIZE --noheadings)
    status=$?
    if [[ $status -ne 0 ]]; then
        exit $status
    fi
    echo "$val"
}

function is_lvm(){
    val=$( /usr/bin/lsblk "$1" --noheadings -o TYPE )
    status=$?
    if [[ status -ne 0 ]]; then
        echo $status
        exit 1
    fi
    if [[ "$val" != "lvm"  ]]; then
        echo "device $device_name is not of lvm type"
        exit 1
    fi
}

function parse_uuid() {
    uuid=$(echo "$1"| awk '{print $1}'|awk -F'UUID=' '{print $2}')
    val=$(/usr/bin/lsblk /dev/disk/by-uuid/"$uuid" -o NAME --noheadings)
    ret=$?
    if [[ ret -ne 0 ]]; then
        echo "Failed to retrieve device name from UUID"
        exit 1
    fi
    echo "/dev/mapper/$val"
}


function shrink_volume() {
    /usr/sbin/lvreduce --resizefs -L "$2b" "$1"
}

function process_entry() {
    expected_size_in_bytes=$(parse_tag "$2")
    if [[ -z "$expected_size_in_bytes" ]]; then
        echo "Tag $SHRINK_TAG not found for device '$1' in '$2'"
        exit 0
    fi
    current_size=$(get_current_volume_size "$1")
    if [[ $current_size -lt $expected_size_in_bytes ]];then
        echo "Unable to shrink: current volume size of $current_size is lower to expected $expected_size_in_bytes"
        exit 0
    fi
    if [[ $current_size -eq $expected_size_in_bytes ]]; then
        echo "Unable to shrink: current volume size of $current_size is equal to expected $expected_size_in_bytes"
        exit 0
    fi
    is_lvm "$1"
    is_device_mounted "$1"
    shrink_volume "$1" "$expected_size_in_bytes"
}

function main() {

    local device_name
    for i in "$@"
    do
    case $i in
        -d=*|--device=*)
        device_name="${i#*=}"
        ;;
        -h)
        echo "Program to shrink an ext4 file system hosted in a Logical Volume. It retrieves the new size from the value of the option named systemd.shrinkfs captured in the /etc/fstab entry of the device. 
        
        Usage: '$(basename "$0")' [-h] [-d=|--device=]

        Example:

        where:
            -h show this help text
            -d|--device= name or UUID of the device that holds an ext4 file system in /etc/fstab to shrink. It maps to the first column in the /etc/fstab file"
        exit 0
        ;;
        *)
                # unknown option
        echo "Unknown flag $i"
        exit 1
        ;;
    esac
    done

    entry=$(read_fstab)
    if [[ -z $entry ]]; then
        echo "Device '$device_name' not found in fstab"
        exit 1
    fi
    process_entry "$(get_device_name "$entry")" "$(awk '{print $4}' <<< "$entry")"
}

main "$@"