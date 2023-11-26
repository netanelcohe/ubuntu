check_for_free_space() {
                echo "Searching for free space on the machine"
        if [ $(parted /dev/sda print free | grep 'Free Space' | awk '{print $3}' | grep GB) ]; then
                unallocated_space=$(parted /dev/sda print free | grep 'Free Space' | awk '{print $3}' | grep GB)
                echo "Found $unallocated_space of not allocated space"
                echo "Current total storage is $(df -h / | awk 'FNR == 2 {print $2}')"
                echo "Allocating to root partition"
                parted /dev/sda resizepart 3 100% >> /dev/null
                pvresize /dev/sda3 > /dev/null 2>&1
                lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv > /dev/null 2>&1
                resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv > /dev/null 2>&1
                echo "Allocation completed."
                echo "New total storage is $(df -h / | awk 'FNR == 2 {print $2}')"
        else
                echo "No free space to allocate"
        fi

}

check_for_free_space
