#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim: ai ts=4 sts=4 et sw=4 nu


from __future__ import (unicode_literals, absolute_import,
                        division, print_function)

import subprocess
import sys


MOUNT_CMD = '/bin/mount'
FSTAB_PATH = '/etc/fstab'

# nagios exit code
STATUS_OK = 0
STATUS_WARNING = 1
STATUS_ERROR = 2
STATUS_UNKNOWN = 3


def main():

    # Get mount output
    p = subprocess.Popen(MOUNT_CMD, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    mount, err = p.communicate()

    if p.returncode != 0 or not mount:
        print("MOUNT ERROR: %s" % err)
        return STATUS_ERROR

    mount = set(mount.splitlines())

    # Get fstab
    with open(FSTAB_PATH) as f:
        fstab = f.readlines()

    # Compare fstab entries to mount output
    for mount_point in [l.replace('\t', ' ').split(' ')[1] for l in fstab if not l.startswith('#') and l != '\n']:
        if mount_point and mount_point != 'none' and mount_point != 'swap':
            # Try to find mount point in mount output
            mount_line = [l for l in mount if mount_point in l.split(' ')]
            if not mount_line:
                print("%s is not mounted" % mount_point)
                return STATUS_ERROR

            assert(len(mount_line) == 1)
            mount_line = mount_line[0]

            # Check mount options
            mount_options = mount_line.split(" ")[-1][1:-1].split(",")

            if 'ro' in mount_options:
                print("%s is read only" % mount_point)
                return STATUS_ERROR

            if 'rw' not in mount_options:
                print("%s is not read write" % mount_point)
                return STATUS_ERROR

            # :TODO:maethor:151123: test write file in partition ?

    print("All mount points are OK")
    return STATUS_OK

if __name__ == "__main__":
    sys.exit(main())
