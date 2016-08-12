#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim: ai ts=4 sts=4 et sw=4 nu

#
# Guillaume Subiron, Sysnove, 2016
#
# Copyright 2016 Guillaume Subiron <guillaume@sysnove.fr>
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more
# details.
#

from __future__ import (unicode_literals, absolute_import,
                        division, print_function)

import subprocess
import sys

# nagios exit code
STATUS_OK = 0
STATUS_WARNING = 1
STATUS_ERROR = 2
STATUS_UNKNOWN = 3

def main():
    p = subprocess.Popen('pg_lsclusters', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lsclusters, err = p.communicate()

    if p.returncode != 0 or not lsclusters:
        print("pg_lsclusters error: %s" % err)
        return STATUS_ERROR

    lsclusters = lsclusters.splitlines()

    down = list()
    online = list()

    for cluster in lsclusters[1:]:
        cluster = cluster.split()
        if cluster[3] == 'down':
            down.append(cluster[0])

        if cluster[3] == 'online':
            online.append(cluster[0])

    if down:
        print("PG cluster %s is down" % ', '.join(down))
        return STATUS_WARNING
    else:
        print("PG cluster %s is online" % ', '.join(online))
        return STATUS_OK

if __name__ == "__main__":
    sys.exit(main())
