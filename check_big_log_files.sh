#!/bin/bash

files=$(nice -n 19 find / -size +1G \( -name "*.log" -o -name catalina.out \))

if [ -z "$files" ]; then
    echo "OK: No crazy log file found."
    exit 0
else
    if [ $(echo $files | wc -l) -eq 1 ]; then
        echo "WARNING: $files size is bigger than 1Go."
    else
        echo "WARNING: $(echo $files | wc -l) log files are bigger than 1Go."
    fi
    exit 1
fi
