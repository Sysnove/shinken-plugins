#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim: ai ts=4 sts=4 et sw=4 nu


from __future__ import (unicode_literals, absolute_import,
                        division, print_function)

import subprocess
import sys
import re

# nagios exit code
STATUS_OK = 0
STATUS_WARNING = 1
STATUS_ERROR = 2
STATUS_UNKNOWN = 3


def main():

    try:
        p = subprocess.Popen(["/usr/sbin/gnt-cluster", "verify"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = p.communicate()
    except Exception as e:
        print(e)
        return STATUS_UNKNOWN

    if err:
        print(err.splitlines()[0])
        return STATUS_UNKNOWN

    ret_code = STATUS_OK
    ret_out = []

    for line in out.splitlines():
        match = re.search('.* - (WARNING|ERROR): (.*)', line)
        if match:
            status = match.group(1)
            msg = match.group(2)
            if status == "WARNING":
                ret_code = max(ret_code, STATUS_WARNING)
            if status == "ERROR":
                ret_code = max(ret_code, STATUS_ERROR)
            ret_out.append('%s: %s' % (status, msg))

    if ret_code == STATUS_OK:
        print("Ganeti cluster is OK")
    else:
        print('\n'.join(ret_out))
    return ret_code

if __name__ == "__main__":
    sys.exit(main())
