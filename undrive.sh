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

  A simple bash script to get rid of your Unraid USB Boot Drive

  *** A bit outdated. Must ./update from raw-gadget/dummy_hcd ***

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
    id_vendor=$(udevadm info --query=all --name="$drive" | grep -E "ID_VENDOR_ID" | awk -F= '{print "0x"$2}')
    id_product=$(udevadm info --query=all --name="$drive" | grep -E "ID_MODEL_ID" | awk -F= '{print "0x"$2}')
    
    if [ -z "$usb_serial" ] || [ -z "$id_vendor" ] || [ -z "$id_product" ]; then
        echo "Could not retrieve all required information for $drive."
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
    
    current_dir=$(pwd)
    
    mkdir $current_dir/undrive
    cd $current_dir/undrive
    git clone https://github.com/xairy/raw-gadget.git > /dev/null 2>&1
    cd raw-gadget/dummy_hcd
    make > /dev/null 2>&1
    cp dummy_hcd.ko /lib/modules/$(uname -r)/kernel/drivers/usb/gadget/
    depmod -a
    
    clone_usb
    
    cat > /etc/modprobe.d/undrive.conf << EOF
install dummy_hcd /sbin/modprobe --ignore-install dummy_hcd; /bin/sleep 3
install g_mass_storage /bin/sleep 2; /sbin/modprobe --ignore-install g_mass_storage
options g_mass_storage file=$image_file idVendor=$id_vendor idProduct=$id_product iManufacturer=Undrive iProduct=UndriveVirtualUSB iSerialNumber=$usb_serial
EOF
    
    echo -e 'dummy_hcd\ng_mass_storage' >> /etc/modules-load.d/modules.conf
    
    modprobe dummy_hcd
    modprobe g_mass_storage
    
    rm -r $current_dir/undrive
    
    echo -e "Done! :)"
    
}

main