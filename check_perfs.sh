#!/bin/bash
# Basic check to test for CPU and IO performances

RET=0

export LC_NUMERIC="C.UTF-8"

for cpu in /sys/devices/system/cpu/cpu*; do
    if [ -f "$cpu/cpufreq/cpuinfo_cur_freq" ]; then
        cpuid=$(basename "$cpu")
        cur=$(cat "$cpu/cpufreq/cpuinfo_cur_freq")
        min=$(cat "$cpu/cpufreq/cpuinfo_min_freq") 
        if [ "$cur" -lt "$min" ]; then
            echo "WARNING : $cpuid current frequency ($cur Mhz) is lower than min frequency ($min Mhz)"
            RET=1
        fi
    fi
done

test_command () {
    c=$1
    t=$2

    TIMEFORMAT=%R
    TIME=$( { time $c > /dev/null; } 2>&1 )
    #echo "$TIME"

    if (( $(echo "$TIME > $t" |bc -l) )); then
        echo "WARNING : \`$c\` took more than ${t}s"
        RET=1
    fi
}

test_command pydf 1
tmpfile=$(mktemp /tmp/check_perfs.XXXXXX)
test_command "dd if=/dev/zero of=$tmpfile bs=1024 count=2000 status=none" 0.05
test_command "python3 -c 'var=1+1'" 0.5

if [ $RET -eq 0 ]; then
    echo "OK : Everything seems fine."
fi

exit $RET
