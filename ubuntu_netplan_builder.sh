#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "[-] This script requires superuser privileges. Please run with 'sudo'"
    exit 1
fi

display_headline() {
    local message="$1"
    local padding="####"
    local headline="$padding $message $padding"
    local character_count=${#headline}
    
    # Echo the '#' character 'character_count' times
    echo
    for ((i = 0; i < character_count; i++)); do
        echo -n "#"
    done
    echo
    # Echo the headline
    echo "$headline"
    # Echo the second set of '#' characters
    for ((i = 0; i < character_count; i++)); do
        echo -n "#"
    done
    echo
    echo
}

validate_dns_servers() {
    local input="$1"

    # Check if the input matches the format (IP1,IP2,IP3,...)
    if [[ $input =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(,[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)*$ ]]; then
        local IFS=','  # Set the field separator to comma
        read -ra dns_servers <<< "$input"  # Split the input by comma
        for server in "${dns_servers[@]}"; do
            if ! validate_ip "$server"; then
                return 1  # Invalid IP address
            fi
        done
        return 0  # Valid format and all IP addresses are valid
    else
        return 1  # Invalid format
    fi
}

ip_to_binary() {
    local ip="$1"
    IFS='.' read -r -a ip_octets <<< "$ip"
    local binary_ip=""
    
    for octet in "${ip_octets[@]}"; do
        binary_ip+=$(printf "%08d" $(bc <<< "obase=2; $octet"))
    done
    
    echo "$binary_ip"
}

validate_gateway() {
    local ip_address="$1"
    local gateway="$2"
    local subnet="$3"
    
    local binary_ip="$(ip_to_binary "$ip_address")"
    local binary_gateway="$(ip_to_binary "$gateway")"

    # Check if the first '  ' bits match
    if [ "${binary_ip:0:subnet}" == "${binary_gateway:0:subnet}" ]; then
        return 0
    else
        return 1 
    fi
}

validate_ip() {
    local ip="$1"
    local ip_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"

    if [[ "$ip" =~ $ip_regex ]]; then
        return 0  
    else
        return 1  
    fi
}

validate_subnet_mask() {
    local mask="$1"

    if [[ "$mask" =~ ^[0-9]+$ && "$mask" -ge 8 && "$mask" -le 24 ]]; then
        return 0  
    else
        return 1  
    fi
}

validate_yes_no() {
    local input="$1"
    case "$input" in
        [Yy]|[Yy][Ee][Ss]|[Nn]|[Nn][Oo]|y|n)
            return 0  # Valid input
            ;;
        *)
            return 1  # Invalid input
            ;;
    esac
}

validate_dhcp_static() {
    local input="$1"
    case "$input" in
        [Dd][Hh][Cc][Pp]|[Ss][Tt][Aa][Tt][Ii][Cc]|dhcp|static)
            return 0  # Valid input
            ;;
        *)
            return 1  # Invalid input
            ;;
    esac
}

map_up_nics() {
    # Get a list of all NICs and their link status
    nic_list=$(ip -o link show | awk -F': ' '{print $2}')

    # Initialize an array to store NICs and their statuses
    nic_statuses=()

    # Iterate through all NICs
    for nic in $nic_list; do
        # Exclude interfaces with names starting with "veth"
        if [[ "$nic" == veth* ]]; then
            continue
        fi

        # Check if the NIC name matches patterns "ens*", "eth*", or "enp*"
        case "$nic" in
            ens*|eth*|enp*|eno*)
                link_status=$(ip link show "$nic" | grep -o "state .*" | awk '{print $2}')
                nic_statuses+=("$nic, Status: $link_status")
				echo "Detected NIC: $nic, Status: $link_status"
                ;;
        esac
    done

    # Check if any NICs were found
    if [[ ${#nic_statuses[@]} -eq 0 ]]; then
        echo "Error: No network interfaces found. Please check the configuration."
        exit 1
    fi
	
    # Check the number of NICs detected and call the appropriate function
    if [[ ${#nic_statuses[@]} -eq 1 ]]; then
        echo "One interface was detected"
        # Print the NICs and their statuses
        for nic_status in "${nic_statuses[@]}"; do
            echo "$nic_status"
        done
    elif [[ ${#nic_statuses[@]} -ge 2 ]]; then
        echo "${#nic_statuses[@]} Interfaces were detected"
        # Print the NICs and their statuses
        for nic_status in "${nic_statuses[@]}"; do
            echo "$nic_status"
        done
    elif [[ ${#nic_statuses[@]} -eq 0 ]]; then
        echo "Error: Unsupported number of network interfaces detected."
    fi
        choose_netplan_structure "${nic_statuses[@]}"
}

choose_netplan_structure() {
    echo "Choose your networking configuration:"
    echo "1. Single NIC"
    echo "2. Single NIC + Trunk port"
    echo "3. Multiple NIC"
    echo "4. Multiple NIC + Trunk port"
	echo
    read -p "Enter the number of your choice (1-4): " choice

    case $choice in
        1)
            single_nic "${nic_statuses[@]}"
            ;;
        2)
			single_nic_trunk "${nic_statuses[@]}"
            ;;
        3)
			multiple_nics "${nic_statuses[@]}"
            ;;
        4)
			multiple_nics_trunk "${nic_statuses[@]}"
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 4."
			choose_netplan_structure
            ;;
    esac
}

ask_4_nic_details(){
    while true; do
    read -p "Configure NIC $nic_name as Static or DHCP? (static/dhcp): " stat_dhcp
    if validate_dhcp_static "$stat_dhcp"; then
        break
    else
        echo "Invalid input. Please enter 'dhcp' or 'static'."
    fi
	done
		if [ "$stat_dhcp" = "static" ]; then
			while true; do
				read -p "Enter the IP address for $nic_name [e.g: 192.168.14.100]: " ip_address
				if validate_ip "$ip_address"; then
					break
				else
					echo "Invalid IP address. Please enter a valid IP address."
				fi
			done
	
			while true; do
				read -p "Enter the netmask for $nic_name [e.g: 24]: " netmask
				if validate_subnet_mask "$netmask"; then
					break
				else
					echo "Invalid subnet mask. Please enter a valid subnet mask."
				fi
			done
			
			while true; do
				read -p "Enter the default gateway IP address for $nic_name [e.g: 192.168.14.1]: " gateway
				if validate_ip "$gateway" && validate_gateway "$ip_address" "$gateway" "$netmask"; then
					break
				else
					echo "Default gateway is not valid or out of range, try again."
				fi
			done
			
			while true; do
				read -p "Enter the DNS servers for $nic_name (comma-separated) [e.g: 8.8.8.8,1.1.1.1]: " nameservers
				if validate_dns_servers "$nameservers"; then
					break
				else
					echo "Invalid DNS server format or one or more IP addresses are invalid."
				fi
			done
				
	
cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
      addresses: [$ip_address/$netmask]
      nameservers:
        addresses: [$nameservers]
      routes:
        - to: default
          via: $gateway
          metric: $metric
EOF
                metric=$(($metric+10))
        else
cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
      dhcp4: yes
      dhcp4-overrides:
        route-metric: $metric
EOF
                metric=$(($metric+10))
         fi
}

single_nic(){
	echo "Starting single NIC configuration"
    local nic_statuses=("$@")
	local metric=60
    cat <<EOF > /etc/netplan/00-installer-config.yaml.tmp
network:
  version: 2
  ethernets:
EOF

    PS3="Choose the NIC to configure as single NIC (enter the number): "
    select interface in "${nic_statuses[@]}"; do
        if [[ -n "$interface" ]]; then
            break
        else
            echo "Invalid selection. Please choose a valid number."
        fi
        done
	nic_name=$(echo "$interface" | awk -F', Status: ' '{print $1}')
	
cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
    $nic_name:
EOF
	ask_4_nic_details
	validate_netplan
}

single_nic_trunk(){
	echo "Starting single NIC + trunk configuration"
    local nic_statuses=("$@")
	local metric=60
    cat <<EOF > /etc/netplan/00-installer-config.yaml.tmp
network:
  version: 2
  ethernets:
EOF

    PS3="Choose the NIC to configure as trunk port connected (enter the number): "
    select interface in "${nic_statuses[@]}"; do
        if [[ -n "$interface" ]]; then
            break
        else
            echo "Invalid selection. Please choose a valid number."
        fi
        done
	trunk_nic_name=$(echo "$interface" | awk -F', Status: ' '{print $1}')
	
cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
    $trunk_nic_name:
EOF

cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
      optional: true
  vlans:
EOF
    read -p "Enter the VLAN ID(s) for $trunk_nic_name (comma-separated, [e.g: 10,100,200]): " vlan_ids
	echo "user defined the VLANs $vlan_ids"
    for vlan_id in $(echo $vlan_ids | sed "s/,/ /g"); do
        while true; do
			read -p "Should VLAN $vlan_id be configured as DHCP or static? (dhcp/static): " vlan_mode
			if validate_dhcp_static "$vlan_mode"; then
			break
		else
			echo "Invalid input. Please enter 'dhcp' or 'static'."
		fi
		done
        if [ "$vlan_mode" = "dhcp" ]; then
cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
    vlan.$vlan_id:
      id: $vlan_id
      link: $trunk_nic_name
      dhcp4: yes
      dhcp4-overrides:
        route-metric: $metric
EOF
        else
            while true; do
                read -p "Enter the IP address for VLAN $vlan_id [e.g: 192.168.14.100]: " vlan_ip
                if validate_ip "$vlan_ip"; then
                    break
                else
                    echo "Invalid IP address. Please enter a valid IP address."
                fi
            done

            while true; do
                read -p "Enter the netmask for VLAN $vlan_id [e.g: 24]: " vlan_netmask
                if validate_subnet_mask "$vlan_netmask"; then
                    break
                else
                    echo "Invalid subnet mask. Please enter a valid subnet mask."
                fi
            done

			while true; do
				read -p "Enter the default gateway IP address for $vlan_id [e.g: 192.168.14.1]: " gateway
				if validate_ip "$gateway" && validate_gateway "$ip_address" "$gateway" "$netmask"; then
					break
				else
					echo "Default gateway is not valid or out of range, try again."
				fi
			done

			while true; do
				read -p "Enter the DNS servers for $vlan_id (comma-separated) [e.g: 8.8.8.8,1.1.1.1]: " nameservers
				if validate_dns_servers "$nameservers"; then
					break
				else
					echo "Invalid DNS server format or one or more IP addresses are invalid."
				fi
			done

cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
    vlan.$vlan_id:
      id: $vlan_id
      link: $trunk_nic_name
      addresses: [$vlan_ip/$vlan_netmask]
      nameservers:
        addresses: [$nameservers]
      routes:
        - to: default
          via: $gateway
          metric: $metric
EOF
        fi
    metric=$(($metric+10))
    done
}

multiple_nics(){
	echo "Starting multiple NICs configuration"
    local nic_statuses=("$@")
	local metric=60
    cat <<EOF > /etc/netplan/00-installer-config.yaml.tmp
network:
  version: 2
  ethernets:
EOF
	for nic_status in "${nic_statuses[@]}"; do
		nic_name=$(echo "$nic_status" | awk -F', Status: ' '{print $1}')
		while true; do
			read -p "Would you like to configure NIC: $nic_status? (yes/no): " choice
			if validate_yes_no "$choice"; then
			break
		else
			echo "Invalid input. Please enter 'yes' or 'no' or 'y' or 'n'."
		fi
		done
		
		if [ "$choice" != "yes" ]; then
			continue
		fi
cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
    $nic_name:
EOF
	ask_4_nic_details
	done
}

multiple_nics_trunk(){
	echo "Staring multiple NICs + trunk configuration"
	local nic_statuses=("$@")
	local metric=60
cat <<EOF > /etc/netplan/00-installer-config.yaml.tmp
network:
  version: 2
  ethernets:
EOF
	PS3="Choose the NIC to configure as trunk port connected (enter the number): "
    select trunk_nic in "${nic_statuses[@]}"; do
        if [[ -n "$trunk_nic" ]]; then
            break
        else
            echo "Invalid selection. Please choose a valid number."
        fi
        done
	trunk_nic_name=$(echo "$trunk_nic" | awk -F', Status: ' '{print $1}')
	
cat <<EOF > /etc/netplan/trunk-config.yaml.tmp
    $trunk_nic_name:
      optional: true
  vlans:
EOF

	read -p "Enter the VLAN ID(s) for $trunk_nic_name (comma-separated, [e.g: 10,100,200]): " vlan_ids
    for vlan_id in $(echo $vlan_ids | sed "s/,/ /g"); do
        while true; do
			read -p "Should VLAN $vlan_id be configured as DHCP or static? (dhcp/static): " vlan_mode
			if validate_dhcp_static "$vlan_mode"; then
			break
		else
			echo "Invalid input. Please enter 'dhcp' or 'static'."
		fi
		done
        if [ "$vlan_mode" = "dhcp" ]; then
cat <<EOF >> /etc/netplan/trunk-config.yaml.tmp
    vlan.$vlan_id:
      id: $vlan_id
      link: $trunk_nic_name
      dhcp4: yes
      dhcp4-overrides:
        route-metric: $metric
EOF
        else
            while true; do
                read -p "Enter the IP address for VLAN $vlan_id [e.g: 192.168.14.100]: " vlan_ip
                if validate_ip "$vlan_ip"; then
                    break
                else
                    echo "Invalid IP address. Please enter a valid IP address."
                fi
            done

            while true; do
                read -p "Enter the netmask for VLAN $vlan_id [e.g: 24]: " vlan_netmask
                if validate_subnet_mask "$vlan_netmask"; then
                    break
                else
                    echo "Invalid subnet mask. Please enter a valid subnet mask."
                fi
            done
			
			while true; do
				read -p "Enter the default gateway IP address for $vlan_id [e.g: 192.168.14.1]: " gateway
				if validate_ip "$gateway" && validate_gateway "$ip_address" "$gateway" "$netmask"; then
					break
				else
					echo "Default gateway is not valid or out of range, try again."
				fi
			done

			while true; do
				read -p "Enter the DNS servers for $vlan_id (comma-separated) [e.g: 8.8.8.8,1.1.1.1]: " nameservers
				if validate_dns_servers "$nameservers"; then
					break
				else
					echo "Invalid DNS server format or one or more IP addresses are invalid."
				fi
			done
cat <<EOF >> /etc/netplan/trunk-config.yaml.tmp
    vlan.$vlan_id:
      id: $vlan_id
      link: $trunk_nic_name
      addresses: [$vlan_ip/$vlan_netmask]
      nameservers:
        addresses: [$nameservers]
      routes:
        - to: default
          via: $gateway
          metric: $metric
EOF
        fi
                metric=$(($metric+10))
    done	
	
	# Create a copy of nic_statuses to preserve the original list
	available_nics=("${nic_statuses[@]}")
	
	# Loop to remove the selected NIC (nic_name) from available_nics
	for ((i = 0; i < ${#available_nics[@]}; i++)); do
		if [[ "${available_nics[i]}" == "$trunk_nic_name, Status: "* ]]; then
			unset available_nics[i]
			break  # Exit the loop after removing the NIC
		fi
	done
		for nic_status in "${available_nics[@]}"; do
		nic_name=$(echo "$nic_status" | awk -F', Status: ' '{print $1}')
		while true; do
			read -p "Would you like to configure NIC: $nic_status? (yes/no): " choice
			if validate_yes_no "$choice"; then
			break
		else
			echo "Invalid input. Please enter 'yes' or 'no' or 'y' or 'n'."
		fi
		done		
		if [ "$choice" != "yes" ]; then
			continue
		fi
cat <<EOF >> /etc/netplan/00-installer-config.yaml.tmp
    $nic_name:
EOF
	ask_4_nic_details
	done
	cat /etc/netplan/trunk-config.yaml.tmp >> /etc/netplan/00-installer-config.yaml.tmp
}

validate_netplan() {
    echo 
    echo "############################################"
    echo 
    echo "Validating network configuration. Please wait..."
        mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bkp
        cp /etc/netplan/00-installer-config.yaml.tmp /etc/netplan/00-installer-config.yaml
    # Run netplan try in the background and redirect output to a temporary file
    netplan try > /tmp/netplan_try_output 2>&1 &
    local netplan_try_pid=$!

    # Wait for up to 20 seconds for netplan try to finish
    local timeout_seconds=20
    local elapsed_seconds=0

    while [[ $elapsed_seconds -lt $timeout_seconds ]]; do
        if ps -p $netplan_try_pid > /dev/null; then
            # Netplan try is still running, sleep for 1 second and increment elapsed time
            sleep 1
            ((elapsed_seconds++))
        else
            # Netplan try has finished, break out of the loop
            break
        fi
    done

    # Check if the output file exists
    if [[ -f "/tmp/netplan_try_output" ]]; then
        # Read the contents of the file into try_output and remove the file
        local try_output
        try_output=$(cat /tmp/netplan_try_output)
        rm /tmp/netplan_try_output

        # Check if the output contains the expected message
        if echo "$try_output" | grep -q "Press ENTER before the timeout to accept the new configuration"; then
            echo "Netplan configuration is OK, but not applied yet."
	    echo "You can find the new netplan file under /etc/netplan/00-installer-config.yaml"
	    echo "To apply the changes, run: sudo netplan apply"
	    echo "GOOD LUCK!"
            return 0
                else
                        # Display an error message if validation fails
                        echo "Error: The Netplan configuration is invalid or timed out. Reverting..."
						echo "$try_output"
                        # Reverting to backup netplan
                        cat /etc/netplan/00-installer-config.yaml.bkp > /etc/netplan/00-installer-config.yaml
                        echo "############################################"
                        echo  "Please check your settings and try again"
                        echo "############################################"
                        map_up_nics
                fi
        fi
    return 1
}

display_headline "Networking Configuration"
map_up_nics

