#!/usr/bin/env python3

#
# Guillaume Subiron, Sysnove, 2016
#
# Description :
#
# TODO
#
# Copyright 2013 Guillaume Subiron <guillaume@sysnove.fr>
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
#

import sys
import re

# nagios exit code
STATUS_OK = 0
STATUS_WARNING = 1
STATUS_ERROR = 2
STATUS_UNKNOWN = 3

def main():
    try:
        with open('/proc/drbd') as f:
            for line in f:
                match = re.search('^\ *(.*): cs:(.*) ro:([^\ ]*) ds:([^\ ]*) .*$', line)
                if match:
                    id = match.group(1)
                    cs = match.group(2)
                    ro = match.group(3)
                    ds = match.group(4)
                    if cs not in ('Connected', 'SyncSource', 'SyncTarget') or 'Unknown' in ro or 'Unknown' in ds:
                        print('DRBD %s state is %s (ro:%s, ds:%s)' % (id, cs, ro, ds))
                        return STATUS_ERROR

            print('DRDB is OK')
            return STATUS_OK
    except IOError as e:
        print(e)
        return STATUS_UNKNOWN

if __name__ == "__main__":
    sys.exit(main())
