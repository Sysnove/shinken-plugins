#!/bin/bash

OK=0
WARNING=1
CRITICAL=2 

CERTS_DIR=/etc/letsencrypt/live

THRESHOLD=30

warnings=""
errors=""

nb_certs=0

for cert in $(sudo find /etc/letsencrypt/live -name "cert.pem"); do
    nb_certs=$[$nb_certs + 1]
    domain=$(basename $(dirname $cert))

    crt_end_date=$(openssl x509 -in "$cert" -noout -enddate | sed -e "s/.*=//")
    date_crt=$(date -ud "$crt_end_date" +"%s")
    date_today=$(date +'%s')
    date_jour_diff=$(( ( $date_crt - $date_today ) / (60*60*24) ))
    if [ $date_jour_diff -le $THRESHOLD ] ; then
        if [ $date_jour_diff -le 0 ] ; then
            errors="$errors $domain"
        else
            warnings="$warnings $domain"
        fi
    fi
done

if ! [ -z "$errors" ]; then
    echo "CRITICAL -$errors certificate is expired!"
    exit $CRITICAL
fi

if ! [ -z "$warnings" ]; then
    echo "WARNING -$warnings certificate will expire in less than $THRESHOLD days!"
    exit $WARNING
fi

echo "OK - $nb_certs certificates."
exit $OK
