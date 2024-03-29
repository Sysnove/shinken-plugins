#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# vim: ai ts=4 sts=4 et sw=4 nu


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
        p = subprocess.Popen(
            ["/usr/sbin/gnt-cluster", "verify", "--error-codes"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        out, err = p.communicate()
    except Exception as e:
        print(e)
        return STATUS_UNKNOWN

    if err:
        print(err.splitlines()[0])
        return STATUS_UNKNOWN

    ret_code = STATUS_OK
    ret_out = []

    # ftype:ecode:edomain:name:msg
    # List of ecodes can be found in `gnt-cluster verfify` man page:
    # http://docs.ganeti.org/ganeti/2.7/html/man-gnt-cluster.html#verify
    status_re = re.compile(
        r'^.* +- (?P<ftype>WARNING|ERROR):'
        + r'(?P<ecode>\w+):(?P<edomain>\w+):'
        + r'(?P<name>[\w.-]+):(?P<msg>.*)$'
    )

    for line in out.splitlines():
        line = line.decode('utf-8')
        match = status_re.match(line)
        if match:
            status = match.group('ftype')
            ecode = match.group('ecode')
            msg = match.group('msg')
            name = match.group('name')

            if ecode == 'ENODEDRBDHELPER' and status == 'WARNING':
                # Ignore DRBD version mismatch warning.
                status = 'OK'

            if ecode == 'ENODEN1':
                # Consider N+1 fault as warning and not error.
                status = "WARNING"

            if status == "WARNING":
                ret_code = max(ret_code, STATUS_WARNING)
            if status == "ERROR":
                ret_code = max(ret_code, STATUS_ERROR)
            ret_out.append('%s - %s: %s' % (status, name, msg))

    if ret_code == STATUS_OK:
        print("Ganeti cluster is OK")
    else:
        print('\n'.join(ret_out))
    return ret_code


if __name__ == "__main__":
    sys.exit(main())
