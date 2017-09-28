#!/usr/bin/env python2

import subprocess
import csv
import sys

# nagios exit code
STATUS_OK = 0
STATUS_WARNING = 1
STATUS_ERROR = 2
STATUS_UNKNOWN = 3


def hbytes(num):
    i = int(num)
    for x in ['KB', 'MB', 'GB']:
        if i < 1024.0:
            return "%.1f%s" % (i, x)
        i /= 1024.0
    return "%.1f%s" % (i, 'TB')


def main():
    if len(sys.argv) == 1:
        return STATUS_UNKNOWN, ['No path given']
    try:
        quotas = subprocess.check_output(['repquota', '-u', '-O', 'csv', sys.argv[1]],
                                         stderr=subprocess.STDOUT).split('\n')
    except subprocess.CalledProcessError as e:
        if e.returncode != 0:
            return STATUS_UNKNOWN, ['Cannot find quotas on given path']
    reader = csv.DictReader(quotas)

    ret_level = 0
    ret_print = []

    for row in reader:
        if int(row['BlockHardLimit']) != 0:
            percent = int(row['BlockUsed']) * 100 / int(row['BlockHardLimit'])
            if percent > 90:
                ret_level = max(ret_level, STATUS_ERROR)
            elif percent >= 80:
                ret_level = max(ret_level, STATUS_WARNING)
            else:
                ret_level = max(ret_level, STATUS_OK)
            ret_print.append('%s: %s%% (%s/%s)' %
        (row['Utilisateur'], percent, hbytes(row['BlockUsed']), hbytes(row['BlockHardLimit'])))

    return ret_level, ret_print


if __name__ == '__main__':
    level, out = main()
    print('\n'.join(out))
    sys.exit(level)
