#!/bin/bash

FSTAB_FILE='/etc/fstab'
SHRINK_TAG='x-systemd.shrinkfs'
ARRAY_IFS=$'\n'

function read_fstab() {
    local -a entries=()
    while read -r line; do
        case $line in
        \#* )
        ;;
        "" )
        ;;
        UUID=*|/dev/* )
        if [[ "$line" == "$device_name "* || $all_devices == true ]]; then
            entries+=("$line")
            if [[ "$line" == "$device_name "* ]]; then
                break
            fi
        fi
        ;;
        esac
    done < $FSTAB_FILE
    echo "${entries[*]}"
}


function get_device_name() {
    if [[ "$1" == "UUID="* ]]; then
        dev_name=$( parse_uuid "$1" )
    else
        dev_name=$(cut -d " " -f 1 <<< "$1")
    fi
    status=$?
    if [[  status -ne 0 ]]; then
        return $status
    fi
    echo "$dev_name"
    return $status
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
        echo "Device $1 is mounted" >&2
        return 1
    fi
    return 0
}

function get_current_volume_size() {
    val=$(/usr/bin/lsblk -b "$1" -o SIZE --noheadings)
    status=$?
    if [[ $status -ne 0 ]]; then
        return $status
    fi
    echo "$val"
    return 0
}

function is_lvm(){
    val=$( /usr/bin/lsblk "$1" --noheadings -o TYPE 2>&1)
    status=$?
    if [[ status -ne 0 ]]; then
        echo "Failed to list block device properties for $2: $val" >&2
        return 1
    fi
    if [[ "$val" != "lvm"  ]]; then
        echo "Device $device_name is not of lvm type" >&2
        return 1
    fi
    return 0
}

function parse_uuid() {
    uuid=$(/usr/bin/awk '{print $1}'<<< "$1"|/usr/bin/awk -F'UUID=' '{print $2}')
    val=$(/usr/bin/lsblk /dev/disk/by-uuid/"$uuid" -o NAME --noheadings 2>/dev/null)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to retrieve device name for UUID=$uuid" >&2
        return $status
    fi
    echo "/dev/mapper/$val"
    return 0
}


function shrink_volume() {
    /usr/sbin/lvreduce --resizefs -L "$2b" "$1"
    return $?
}


function check_volume_size() {
    current_size=$(get_current_volume_size "$1")
    if [[ $current_size -lt $2 ]];then
        echo "Current volume size for device $1 ($current_size bytes) is lower to expected $2 bytes" >&2
        return 1
    fi
    if [[ $current_size -eq $2 ]]; then
        echo "Current volume size for device $1 already equals $2 bytes" >&2
        return 1
    fi
    return $?
}

function calculate_expected_resized_file_system_size_in_blocks(){
    local device=$1
    increment_boot_partition_in_blocks=$(convert_size_to_fs_blocks "$device" "$INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES")
    total_block_count=$(/usr/sbin/tune2fs -l "$device" | /usr/bin/awk '/Block count:/{print $3}')
    new_fs_size_in_blocks=$(( total_block_count - increment_boot_partition_in_blocks ))
    echo $new_fs_size_in_blocks
}

function check_filesystem_size() {
    local device=$1
    local new_fs_size_in_blocks=$2
    new_fs_size_in_blocks=$(calculate_expected_resized_file_system_size_in_blocks "$device")
    # it is possible that running this command after resizing it might give an even smaller number. 
    minimum_blocks_required=$(/usr/sbin/resize2fs -P "$device" 2> /dev/null | /usr/bin/awk  '{print $NF}')

    if [[ "$new_fs_size_in_blocks" -le "0" ]]; then
        echo "Unable to shrink volume: New size is 0 blocks"
        return 1
    fi
    if [[ $minimum_blocks_required -gt $new_fs_size_in_blocks ]]; then
        echo "Unable to shrink volume: Estimated minimum size of the file system $1 ($minimum_blocks_required blocks) is greater than the new size $new_fs_size_in_blocks blocks" >&2
        return 1
    fi
    return 0
}

function process_entry() {
    is_lvm "$1" "$3"
    status=$?
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    expected_size_in_bytes=$(parse_tag "$2")
    if [[ -z "$expected_size_in_bytes" ]]; then
        echo "Error: Tag $SHRINK_TAG not found for device '$3' in '$2'" >&2
        return 1
    fi
    check_filesystem_size "$1" "$expected_size_in_bytes"
    status=$?
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    check_volume_size "$1" "$expected_size_in_bytes"
    status=$?
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    is_device_mounted "$1"
    status=$?
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    shrink_volume "$1" "$expected_size_in_bytes"
    return $?
}


function display_help() {
    echo "Program to shrink an ext4 file system hosted in a Logical Volume. It retrieves the new size from the value of the option named systemd.shrinkfs captured in the /etc/fstab entry of the device. 
    
    Usage: '$(basename "$0")' [-h] [-d=|--device=|--all]

    Example:

    where:
        -h show this help text
        -d|--device= name or UUID of the device that holds an ext4 file system in /etc/fstab to shrink. It maps to the first column in the /etc/fstab file
        --all processes all devices in the '/etc/fstab' that contains the $SHRINK_TAG option"

}
function parse_flags() {
    for i in "$@"
        do
        case $i in
            --all)
            all_devices=true
            ;;
            -d=*|--device=*)
            if [[ -n $device_name ]]; then
                echo "Only one device flag '-d|--device' is supported"
                exit 1
            fi
            device_name="${i#*=}"
            ;;
            -h)
            display_help
            exit 0
            ;;
            *)
            # unknown option
            echo "Unknown flag $i"
            exit 1
            ;;
        esac
    done
    if [[ $all_devices == true && -n "$device_name" ]]; then
        echo "Invalid combination of flags: --all and -d|--device" >&2
        exit 1
    fi
    if [[ $all_devices == false && -z "$device_name" ]]; then
        display_help
        exit 0
    fi
}

function main() {

    local device_name
    local all_devices=false
    local run_status=0
    
    parse_flags "$@"
    IFS="${ARRAY_IFS}" devices=($(read_fstab))
    if [[ ${#devices[@]} == 0 ]]; then
        if [[ $all_devices == true ]]; then 
            echo "No devices found in '/etc/fstab'" >&2
            exit 1
        fi
        echo "Device '$device_name' not found in fstab" >&2
        exit 1
    fi
  
    for entry in "${devices[@]}"
    do
        device_name=$( get_device_name "$entry" )
        status=$?
        if [[ $status -ne 0 ]]; then
            run_status=$status
            continue
        fi
        opts=$( /usr/bin/awk '{print $4}' <<< "$entry" )
        status=$?
        if [[ $status -ne 0 ]]; then
            run_status=$status
            continue
        fi
        process_entry "$device_name" "$opts" "$( /usr/bin/awk '{print $1}' <<< "$entry" )"
        status=$?
        if [[ $status -ne 0 ]]; then
            run_status=$status
        fi
    done

    exit $run_status
}

main "$@"