#!/bin/bash

header() {
    clear
    cat <<"EOF"
                           _        _
                          | |      (_)
         _   _  _ __    __| | _ __  _ __   __ ___
        | | | || '_ \  / _` || '__|| |\ \ / // _ \
        | |_| || | | || (_| || |   | | \ V /|  __/
         \__,_||_| |_| \__,_||_|   |_|  \_/  \___|

  A simple bash script to get rid of your Unraid USB boot drive

EOF
}


clone_usb() {
    # Get list of devices
    devices=$(lsblk -dpno NAME,SIZE,MODEL | grep -E "/dev/sd")
    
    if [ -z "$devices" ]; then
        echo "No devices found."
        exit 1
    fi
    
    echo -e "\nAvailable devices:"
    echo "$devices"
    
    # Device selection
    echo -e "\nSelect a device to clone:"
    select drive in $(echo "$devices" | awk '{print $1}'); do
        if [ -n "$drive" ]; then
            echo "You selected: $drive"
            break
        else
            echo "Invalid option. Try again."
        fi
    done
    
    usb_serial=$(udevadm info --query=all --name="$drive" | grep -E "ID_SERIAL_SHORT" | awk -F= '{print $2}')
    if [ -z "$usb_serial" ]; then
        echo "Could not retrieve the serial number for $drive."
        exit 1        
    fi

    image_file=${image_file:-/var/lib/vz/images/undrive.img}
    
    # Check if the directory exists
    if [ ! -d "$(dirname "$image_file")" ]; then
        echo "The directory $(dirname "$image_file") does not exist. Please create it first."
        exit 1
    fi
    
    # Start cloning
    echo "Creating an image of $drive at $image_file..."
    dd if="$drive" of="$image_file" bs=4M status=progress conv=fsync
    
    # Ensure the operation completed successfully
    if [ $? -eq 0 ]; then
        echo "The image has been successfully created at $image_file."
    else
        echo "An error occurred during the cloning process."
    fi
}


main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Run this script as root"
        exit 1
    fi
    
    header
    
    COMMAND="apt install -y pve-headers-$(uname -r) gcc git make -y > /dev/null 2>&1"
    echo "Installing dependencies automatically..."
    eval "$COMMAND"
    
    if [[ $? -eq 0 ]]; then
        echo "Dependencies have been installed successfully."
    else
        echo "An error occurred during the installation."
        exit 1
    fi
    
    mkdir /root/undrive
    cd /root/undrive
    git clone https://github.com/xairy/raw-gadget.git > /dev/null 2>&1
    cd raw-gadget/dummy_hcd
    make > /dev/null 2>&1
    cp dummy_hcd.ko /lib/modules/$(uname -r)/kernel/drivers/usb/gadget/
    depmod -a
         
    clone_usb

    echo "options g_mass_storage file=$image_file idVendor=0x0781 idProduct=0x5567 iManufacturer=Undrive iProduct=Undrive Virtual USB iSerialNumber=$usb_serial" > /etc/modprobe.d/undrive.conf
    echo -e 'dummy_hcd\ng_mass_storage' >> /etc/modules-load.d/modules.conf
    modprobe dummy_hcd g_mass_storage

    rm -rf /root/undrive  

    echo -e "Done! :)" 
    
}

main