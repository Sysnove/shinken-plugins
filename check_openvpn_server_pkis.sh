#!/bin/bash

if [ -z "$(compgen -G "/etc/openvpn/*-keys")"  ]; then
    echo "WARNING: no PKI to check, maybe manually installed."
    exit 1
fi

for PKI in /etc/openvpn/*-keys; do
    OUTPUT="$("$(dirname "$0")"/check_pki.sh "${PKI}")"
    EXIT_CODE="$?"
    if [ "$EXIT_CODE" -ne 0 ]; then
        echo "${OUTPUT}" | sed -E 's;^(OK|WARNING|CRITICAL|UNKNOWN): (.*)$;\1: '"${PKI}"' - \2;'
        exit ${EXIT_CODE}
    fi
done

echo "OK: All checked PKI directories are fine."
