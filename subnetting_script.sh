#!/bin/bash

# Function to validate IP address
validate_ip() {
    local ip="$1"
    local ip_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"

    if [[ "$ip" =~ $ip_regex ]]; then
        return 0  
    else
        return 1  
    fi
}

# Function to validate CIDR range
validate_subnet_mask() {
    local mask="$1"

    if [[ "$mask" =~ ^[0-9]+$ && "$mask" -ge 0 && "$mask" -le 32 ]]; then
        return 0  
    else
        return 1  
    fi
}

# Function to calculate subnet mask from CIDR
calculate_subnet_mask() {
    local cidr="$1"
    local subnet_mask=""

    if [ "$cidr" -eq 0 ]; then
        subnet_mask="0.0.0.0"
    else
        full_octets=$(( cidr / 8 ))
        partial_octet=$(( cidr % 8 ))

        for ((i = 0; i < full_octets; i++)); do
            subnet_mask+="255."
        done

        if [ "$full_octets" -lt 4 ]; then
            case $partial_octet in
                0) subnet_mask+="0";;
                1) subnet_mask+="128";;
                2) subnet_mask+="192";;
                3) subnet_mask+="224";;
                4) subnet_mask+="240";;
                5) subnet_mask+="248";;
                6) subnet_mask+="252";;
                7) subnet_mask+="254";;
            esac

            if [ "$full_octets" -lt 3 ]; then
                subnet_mask+="."
                for ((i = full_octets + 1; i < 4; i++)); do
                    subnet_mask+="0."
                done
                subnet_mask=${subnet_mask%?} # Remove the trailing dot
            fi
        fi
    fi

    echo "$subnet_mask"
}

# Function to calculate network size from CIDR
calculate_network_size() {
    local cidr="$1"
    local network_size=$(( 2 ** (32 - cidr) ))

    echo "$network_size"
}

calculate_network_range() {
    local ip="$1"
    local cidr="$2"
    local network_range=""

    IFS='.' read -r -a ip_octets <<< "$ip"
    subnet_size=$(( 2 ** (32 - cidr) ))

    start_range=$(( (ip_octets[0] << 24) + (ip_octets[1] << 16) + (ip_octets[2] << 8) + ip_octets[3] & ~(subnet_size - 1) ))
    end_range=$(( start_range + subnet_size - 1 ))

    start_first_octet=$(( start_range >> 24 & 255 ))
    start_second_octet=$(( start_range >> 16 & 255 ))
    start_third_octet=$(( start_range >> 8 & 255 ))
    start_last_octet=$(( start_range & 255 ))
    
    end_first_octet=$(( end_range >> 24 & 255 ))
    end_second_octet=$(( end_range >> 16 & 255 ))
    end_third_octet=$(( end_range >> 8 & 255 ))
    end_last_octet=$(( end_range & 255 ))
    
    network_range="$start_first_octet.$start_second_octet.$start_third_octet.$start_last_octet-$end_first_octet.$end_second_octet.$end_third_octet.$end_last_octet"

    echo "$network_range"
}

calculate_network_id() {
    local ip="$1"
    local cidr="$2"
    local network_id=""
    
    IFS='.' read -r -a ip_octets <<< "$ip"
    subnet_size=$(( 2 ** (32 - cidr) ))
    
    start_range=$(( (ip_octets[0] << 24) + (ip_octets[1] << 16) + (ip_octets[2] << 8) + ip_octets[3] & ~(subnet_size - 1) ))
    start_first_octet=$(( start_range >> 24 & 255 ))
    start_second_octet=$(( start_range >> 16 & 255 ))
    start_third_octet=$(( start_range >> 8 & 255 ))

    network_id="$start_first_octet.$start_second_octet.$start_third_octet.0"
    
    echo "$network_id"
}

calculate_broadcast_ip() {
    local ip="$1"
    local cidr="$2"
    local broadcast_ip=""

    IFS='.' read -r -a ip_octets <<< "$ip"
    subnet_size=$(( 2 ** (32 - cidr) ))
    
    start_range=$(( (ip_octets[0] << 24) + (ip_octets[1] << 16) + (ip_octets[2] << 8) + ip_octets[3] & ~(subnet_size - 1) ))
    end_range=$(( start_range + subnet_size - 1 ))

    end_first_octet=$(( end_range >> 24 & 255 ))
    end_second_octet=$(( end_range >> 16 & 255 ))
    end_third_octet=$(( end_range >> 8 & 255 ))
    end_last_octet=$(( end_range & 255 ))

    broadcast_ip="$end_first_octet.$end_second_octet.$end_third_octet.$end_last_octet"

    echo "$broadcast_ip"
}

calculate_first_host_ip() {
    local ip="$1"
    local cidr="$2"
    local first_host_ip=""

    network_id=$(calculate_network_id "$ip" "$cidr")
    
    IFS='.' read -r -a ip_octets <<< "$network_id"
    first_host_octet=$(( start_last_octet + 1 ))

    first_host_ip="$((ip_octets[0])).$((ip_octets[1])).$((ip_octets[2])).$first_host_octet"

    echo "$first_host_ip"
}

calculate_last_host_ip() {
    local ip="$1"
    local cidr="$2"
    local last_host_ip=""

    broadcast_ip=$(calculate_broadcast_ip "$ip" "$cidr")
    IFS='.' read -r -a ip_octets <<< "$broadcast_ip"
    
    last_octet=$(( ip_octets[3] - 1 ))
    last_host_ip="$((ip_octets[0])).$((ip_octets[1])).$((ip_octets[2])).$last_octet"

    echo "$last_host_ip"
}

# Validate and obtain user input in a loop until valid
valid_input=false
while ! $valid_input; do
    read -p "Enter IP address in format x.x.x.x/y: " ip_cidr
    
    # Extract IP and CIDR parts
    ip=$(echo "$ip_cidr" | cut -d'/' -f1)
    cidr=$(echo "$ip_cidr" | cut -d'/' -f2)

    # Validate IP address and CIDR range
    if validate_ip "$ip" && validate_subnet_mask "$cidr"; then
        valid_input=true

        # Calculate subnet mask
        subnet_mask=$(calculate_subnet_mask "$cidr")
        echo "Subnet Mask: $subnet_mask"
        
        # Calculate network size
        network_size=$(calculate_network_size "$cidr")
        echo "Network Size: $network_size IP addresses"
        
        # Calculate network ID
        network_id=$(calculate_network_id "$ip" "$cidr")
        echo "Network ID: $network_id"
        
        network_range=$(calculate_network_range "$ip" "$cidr")
        echo "Network Range: $network_range"

        # Calculate broadcast IP address
        broadcast_ip=$(calculate_broadcast_ip "$ip" "$cidr")
        echo "Broadcast IP: $broadcast_ip"
        
        # Calculate first host IP
        first_host_ip=$(calculate_first_host_ip "$ip" "$cidr")
        echo "First Host IP: $first_host_ip"
        
        # Calculate last host IP
        last_host_ip=$(calculate_last_host_ip "$ip" "$cidr")
        echo "Last Host IP: $last_host_ip"
        
        # Further calculations will go here using the subnet mask, network size, network range, broadcast IP, network ID, first host IP, and last host IP
    else
        echo "Invalid input. Please enter a valid IP address in CIDR notation."
    fi
done

