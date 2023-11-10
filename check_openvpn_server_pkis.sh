#!/bin/sh

for PKI in /etc/openvpn/*-keys; do
    if ! OUTPUT="$("$(dirname "$0")"/check_pki.sh "${PKI}")"; then
        EXIT_CODE="$?"
        echo "${OUTPUT}" | sed -E 's/^(OK|WARNING|CRITICAL|UNKNOWN): (.*)$/\1: '"${PKI}"' - \2/'
        exit ${EXIT_CODE}
    fi
done

echo "OK: All checked PKI directories are fine."
