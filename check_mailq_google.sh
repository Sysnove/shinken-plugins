#!/bin/bash

emails_blocked_by_google=$(mailq | grep -c 'https://support.google.com/')

if [ $emails_blocked_by_google -eq 0 ] ; then
    echo "OK - No email blocked by Google in mailq"
    exit 0
else
    echo "CRITICAL - $emails_blocked_by_google emails blocked by Google found in mailq"
    exit 2
fi
