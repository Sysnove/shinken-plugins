#!/bin/sh

# shellcheck disable=SC2009
if pgrep varnishd >/dev/null; then
    varnish_vcl=$(ps faux | grep varnishd | grep -Eo '\-f .*\.vcl' | head -n 1 | cut -d ' ' -f 2)
    if [ -f "$varnish_vcl" ]; then
        if grep -q -E '^ *.probe = {' "$varnish_vcl"; then
            echo "CRITICAL - Probe should be disabled in $varnish_vcl"
            exit 2
        fi
    else
        echo "CRITICAL - vcl file does not exist: $varnish_vcl"
        exit 2
    fi
fi

echo "OK - Varnish VCL is OK"
exit 0
