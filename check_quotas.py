#!/usr/bin/env python3

import subprocess
import csv
import sys
import os

# nagios exit code
STATUS_OK = 0
STATUS_WARNING = 1
STATUS_ERROR = 2
STATUS_UNKNOWN = 3

# Thresholds
THRESHOLD_WARNING = 80
THRESHOLD_ERROR = 90

# Force C locale
myenv = dict(os.environ)
myenv['LC_ALL'] = 'C'


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
                                         stderr=subprocess.STDOUT, env=myenv).split('\n')
    except subprocess.CalledProcessError as e:
        if e.returncode != 0:
            return STATUS_UNKNOWN, ['Cannot find quotas on given path']
    reader = csv.DictReader(quotas)

    ret_level = 0
    ret_print = []

    try:
        for row in reader:
            if int(row['BlockHardLimit']) != 0:
                percent = int(row['BlockUsed']) * 100 / int(row['BlockHardLimit'])
                if percent >= THRESHOLD_ERROR:
                    ret_level = max(ret_level, STATUS_ERROR)
                elif percent >= THRESHOLD_WARNING:
                    ret_level = max(ret_level, STATUS_WARNING)
                else:
                    ret_level = max(ret_level, STATUS_OK)
                ret_print.append('%s: %s%% (%s/%s)' % (row['User'], percent, hbytes(row['BlockUsed']), hbytes(row['BlockHardLimit'])))
    except KeyError:
        return STATUS_UNKNOWN, ['Cannot parse quotas from repquota output']
    return ret_level, ret_print


if __name__ == '__main__':
    level, out = main()
    print('\n'.join(out))
    sys.exit(level)
