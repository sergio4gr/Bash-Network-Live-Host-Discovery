#!/bin/bash

usage() {
	echo "[!] Illegal number of parameters."
	echo "Usage: $0 <cidr_ip_subnet>"
}

header() {
	base64 -d <<<"H4sIAAAAAAAAA6VSy23FMAy7ewre+goU0AKdoycBWkTDl6TsvLTo4QGNHX9I0Q7IoADofU6/nx/svWY1Es1WVZw47srysmCYo4uAR73XRVOMJB6sS2LJMdhhoPFmsbYj1l0XTXGnMApZoBO+wB66YwTSfGrq+bo0rfrV3Gd1isjyJtghIERSQyItJT8Vpnv97dFrz8LN7bup268XTmj0sRzH9zECKX83fDLYs/b7bp1Qx/dwRBPTNCNhW+vu+M5Dbfk2ruQ1TdFPUOO0+EEetfnL9gnFNU6gJ4GQyZHnD3IAGynzT++VjFYf+FcMPh7fDW5rqfkCAAA=" | gunzip
	echo -e "\n"
}

suffix_to_bit_netmask() {
    suffix=$1;
    shift=$(( 32 - suffix ));

    bitmask=""
    for (( i=0; i < 32; i++ )); do
        num=0
        if [ $i -lt $suffix ]; then
            num=1
        fi

        space=
        if [ $(( i % 8 )) -eq 0 ]; then
            space=" ";
        fi

        bitmask="${bitmask}${space}${num}"
    done
    echo $bitmask
}

bit_netmask_to_wildcard_netmask() {
    bitmask=$1;
    wildcard_mask=
    for octet in $bitmask; do
        wildcard_mask="${wildcard_mask} $(( 255 - 2#$octet ))"
    done
    echo $wildcard_mask;
}

check_net_boundary() {
    net=$1;
    wildcard_mask=$2;
    is_correct=1;
    for (( i = 1; i <= 4; i++ )); do
        net_octet=$(echo $net | cut -d '.' -f $i)
        mask_octet=$(echo $wildcard_mask | cut -d ' ' -f $i)
        if [ $mask_octet -gt 0 ]; then
            if [ $(( $net_octet&$mask_octet )) -ne 0 ]; then
                is_correct=0;
            fi
        fi
    done
    echo $is_correct;
}

test_icmp() {
	return 1
	ping -c 1 -W 1 $1 &> /dev/null && return 0
	return 1
}

test_common_tcp() {
	topTenTcp=(80 23 443 21 22 25 3389 110 445 139)
	for port in "${topTenTcp[@]}"
	do
		timeout 1 bash -c "2< /dev/null > /dev/tcp/$1/$port" && return 0	
	done
	return 1
}

test_cidr() {

	# ---------------------------------------
	#  CIDR expansion process
	# ---------------------------------------

	ipList=
	activeHosts=()

	net=$(echo $1 | cut -d '/' -f 1);
	suffix=$(echo $1 | cut -d '/' -f 2);
	do_processing=1;
	
	bit_netmask=$(suffix_to_bit_netmask $suffix);
	wildcard_mask=$(bit_netmask_to_wildcard_netmask "$bit_netmask");
	is_net_boundary=$(check_net_boundary $net "$wildcard_mask");

	if [ $is_net_boundary -ne 1 ]; then
		echo "[!] CIDR invalid. Exiting..."
		do_processing=0;
	fi  

	if [ $do_processing -eq 1 ]; then
		str=
		for (( i = 1; i <= 4; i++ )); do
			range=$(echo $net | cut -d '.' -f $i)
			mask_octet=$(echo $wildcard_mask | cut -d ' ' -f $i)
			if [ $mask_octet -gt 0 ]; then
			range="{$range..$(( $range | $mask_octet ))}";
			fi
			str="${str} $range"
		done
		ips=$(echo $str | sed "s, ,\\.,g"); ## replace spaces with periods, a join...
		ipList=($(eval echo $ips | tr ' ' '\012'))
	fi
	
	# -------------------------------------
	#  Testing individual IP addresses
	# -------------------------------------
	
	trap "exit" INT
	echo "---- Probing CIDR: $1 ----"
	for ip in "${ipList[@]}"
	do
		printf "%s\r" "---> Testing $ip"
		if test_icmp $ip || test_common_tcp $ip; then
			activeHosts+=($ip)
			printf "%s\n" "===> LIVE HOST: $ip"
		fi
	done
}

if [ "$#" -ne 1 ]; then
	usage
else
	header
	test_cidr $1
fi
