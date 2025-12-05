#!/bin/bash

INTERFACE="eth0"

ipv4() {
    ipv4_address=$(
        ip addr show dev $INTERFACE 2>/dev/null |
        grep -w inet |
        awk '{print $2}' |
        cut -d '/' -f 1 |
        tr -d ' '
    )

    if [ -z "$ipv4_address" ]; then
        echo "Error: Could not find an IPv4 address for interface '$INTERFACE'."
        echo "Check if the interface exists or if it has an IP assigned."
        exit 1
    else
        echo "$ipv4_address"
    fi

    exit 0
}