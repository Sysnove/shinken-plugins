#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# vim: ai ts=4 sts=4 et sw=4 nu


import sys
import os
import re


#MOUNT_CMD = "/bin/mount"
#FSTAB_PATH = "/etc/fstab"

# nagios exit code
STATUS_OK = 0
STATUS_WARNING = 1
STATUS_ERROR = 2
STATUS_UNKNOWN = 3


def main():
    mtab_file = "/etc/mtab"
    if not os.path.exists(mtab_file):
        mtab_file = "/proc/mounts"

    with open(mtab_file) as f:
        mtab = [x.strip() for x in f.readlines()]

    mounts = [l for l in mtab if (l.startswith("/") or ":/" in l)]

    ##ISPConfig
    mounts = [
        m
        for m in mounts
        if not (
            m.split(' ')[1].startswith("/var/log/ispconfig/httpd")
            or re.match("^/(srv|var)/www/clients/.*/log", m.split(' ')[1])
        )
    ]

    # Get fstab
    with open('/etc/fstab') as f:
        fstab_lines = [l.strip() for l in f.readlines()]
        fstab_lines = [re.sub(' +', ' ', l.replace('\t', ' ')) for l in fstab_lines]
        fstab_lines = [l for l in fstab_lines if l and (l.startswith("/") or l.startswith('UUID') or ":/" in l) and not (l.startswith('#') or l.startswith("/var/log/ispconfig/httpd"))]
        fstab_lines = [l for l in fstab_lines if l.split(' ')[1] not in ['none', 'swap', '/media/cdrom0', '/media/usb0', '/media/usb1']]
        fstab_lines = [l for l in fstab_lines if l.split(' ')[2] not in ['swap', 'tmpfs']]

    # Compare fstab entries to mount output
    for fstab_line in fstab_lines:
        # Try to find mount point in mount output
        fstab_entry = fstab_line.split()

        # Check mount options
        fstab_options = fstab_entry[3].split(',')

        if "noauto" in fstab_options:
            # Ignore noauto mount points
            continue

        fstab_source = fstab_entry[0]
        fstab_mount_point = fstab_entry[1]

        mount_entries = []

        for mount in mounts:
            mount_entry = mount.split()
            mount_device = mount_entry[0]
            mount_mount_point = mount_entry[1]

            if os.path.samefile(fstab_mount_point, mount_mount_point):
                mount_entries.append(mount_entry)

        if not mount_entries:
            print("%s is not mounted" % fstab_mount_point)
            return STATUS_ERROR

        if len(mount_entries) > 1:
            print("%s found more than one time" % fstab_mount_point)
            return STATUS_ERROR

        mount_entry = mount_entries[0]

        # Check mount options
        mount_options = mount_entry[3].split(",")

        if "ro" in mount_options:
            print("%s is read only" % fstab_mount_point)
            return STATUS_ERROR

        if "rw" not in mount_options:
            print("%s is not read write" % fstab_mount_point)
            return STATUS_ERROR

        # :TODO:maethor:151123: test write file in partition ?

    print("All %s mount points are OK" % len(fstab_lines))
    return STATUS_OK


if __name__ == "__main__":
    sys.exit(main())
