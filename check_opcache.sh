#!/bin/bash

opcache_ok=()
opcache_full=()
interned_strings_full=()

for v in 5.6 7.0 7.2 7.3 7.4 8.0 8.1 8.2 8.3; do
    opcache=$(curl -sL "http://$(cat /etc/hostname.sysnove).sysnove.net/phpinfo-$v.php")
    if echo -r "$opcache" | grep ">opcache.enable<" | grep -q ">On<" ; then
        #memory_consumption=$(echo -r "$opcache" | grep "opcache.memory_consumption" | grep -Eo '[0-9]*' | tail -n 1)
        memory_used=$(($(echo -r "$opcache" | grep ">Used memory" | grep -Eo '[0-9]*') / (1024*1024)))
        memory_free=$(($(echo -r "$opcache" | grep ">Free memory" | grep -Eo '[0-9]*') / (1024*1024)))
        interned_strings_memory_used=$(($(echo -r "$opcache" | grep ">Interned Strings Used memory" | grep -Eo '[0-9]*') / (1024*1024)))
        interned_strings_memory_free=$(($(echo -r "$opcache" | grep ">Interned Strings Free memory" | grep -Eo '[0-9]*') / (1024*1024)))
        cache_hits=$(echo -r "$opcache" | grep "Cache hits" | grep -Eo '[0-9]*')
        cache_misses=$(echo -r "$opcache" | grep "Cache misses" | grep -Eo '[0-9]*')
        #echo $v $memory_consumption $memory_used $memory_free $interned_strings_memory_used $interned_strings_memory_free $cache_hits $cache_misses

        if [ "$memory_free" -eq 0 ]; then
            opcache_full+=("PHP$v (${memory_used}MB)")
            continue
        fi

        if [ "$interned_strings_memory_free" -eq 0 ]; then
            interned_strings_full+=("PHP$v (${interned_strings_memory_used}MB)")
            continue
        fi

        opcache_ok+=("PHP$v $(echo "(($cache_hits + $cache_misses) * 100) / $cache_hits)" | bc)%")
    fi
done

if [ ${#opcache_full[@]} -gt 0 ]; then
    echo "CRITICAL - Some OPcache are full : ${opcache_full[*]}"
    exit 0 # TODO exit 2
elif [ ${#interned_strings_full[@]} -gt 0 ]; then
    echo "WARNING - You should increase opcache.interned_strings_buffer for ${interned_strings_full[*]}"
    exit 0 # TODO exit 1
elif [ ${#opcache_ok[@]} -gt 0 ]; then
    echo "OK - PHP OPcache is working fine for ${opcache_ok[*]}" 
    exit 0
else
    echo "UNKNOWN - Could not find any phpinfo"
    exit 3
fi


