#!/bin/bash

hitrates=()
opcache_ok=()
opcache_underused=()
opcache_full=()
interned_strings_full=()

for v in 5.6 7.0 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4; do
    opcache=$(curl -sL -4 "http://$(cat /etc/hostname.sysnove).sysnove.net/phpinfo-$v.php")
    if echo -r "$opcache" | grep ">opcache.enable<" | grep -q ">On<" ; then
        #memory_consumption=$(echo -r "$opcache" | grep "opcache.memory_consumption" | grep -Eo '[0-9]*' | tail -n 1)
        memory_used=$(($(echo -r "$opcache" | grep ">Used memory" | grep -Eo '[0-9]*') / (1024*1024)))
        memory_free=$(($(echo -r "$opcache" | grep ">Free memory" | grep -Eo '[0-9]*') / (1024*1024)))
        interned_strings_memory_used=$(($(echo -r "$opcache" | grep ">Interned Strings Used memory" | grep -Eo '[0-9]*') / (1024*1024)))
        interned_strings_memory_free=$(($(echo -r "$opcache" | grep ">Interned Strings Free memory" | grep -Eo '[0-9]*') / (1024*1024)))
        cache_hits=$(echo -r "$opcache" | grep "Cache hits" | grep -Eo '[0-9]*')
        cache_misses=$(echo -r "$opcache" | grep "Cache misses" | grep -Eo '[0-9]*')
        #echo $v $memory_consumption $memory_used $memory_free $interned_strings_memory_used $interned_strings_memory_free $cache_hits $cache_misses

        hitrate=$(echo "($cache_hits * 100) / ($cache_hits + $cache_misses)" | bc)
        hitrates+=("php${v}_opcache_hitrate=${hitrate}%")

        if [ "$hitrate" -lt 25 ]; then
            opcache_underused+=("PHP$v (${hitrate}% hitrate)")
            continue
        fi

        if [ "$memory_free" -eq 0 ]; then
            opcache_full+=("PHP$v (${memory_used}MB)")
            continue
        fi

        if [ "$interned_strings_memory_free" -eq 0 ]; then
            interned_strings_full+=("PHP$v (${interned_strings_memory_used}MB)")
            continue
        fi

        opcache_ok+=("PHP$v")
    fi
done

if [ ${#opcache_underused[@]} -gt 0 ]; then
    echo "CRITICAL - Some OPcache hitrates are bad : ${opcache_underused[*]} | ${hitrates[*]}"
    exit 2
elif [ ${#opcache_full[@]} -gt 0 ]; then
    echo "WARNING - Some OPcache are full : ${opcache_full[*]} | ${hitrates[*]}"
    exit 1
elif [ ${#interned_strings_full[@]} -gt 0 ]; then
    echo "WARNING - You should increase opcache.interned_strings_buffer for ${interned_strings_full[*]} | ${hitrates[*]}"
    exit 1
elif [ ${#opcache_ok[@]} -gt 0 ]; then
    echo "OK - PHP OPcache is working fine for ${opcache_ok[*]} | ${hitrates[*]}" 
    exit 0
else
    echo "UNKNOWN - Could not find any phpinfo"
    exit 3
fi


