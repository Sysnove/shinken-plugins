#!/usr/bin/env python3

#
# Alexis Lahouze, Sysnove, 2016
#
# Description :
#
# This plugin checks date in GTFS files in a directory and returns a specific
# status.
#
# Copyright 2016 Alexis Lahouze <alexis@sysnove.fr>
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more
# details.
#
import argparse
import re
import traceback
from os import listdir, path
import sys
from zipfile import ZipFile

import arrow


OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3


def print_message(message, perfdata_str=None):
    if perfdata_str is not None:
        print('%s | %s' % (message, perfdata_str))
    else:
        print(message)


def ok(message, perfdata_str=None):
    print_message('OK - %s' % (message), perfdata_str)
    raise SystemExit(OK)


def warning(message, perfdata_str=None):
    print_message("WARNING - %s" % (message), perfdata_str)
    raise SystemExit(WARNING)


def critical(message, perfdata_str=None):
    print_message("CRITICAL - %s" % (message), perfdata_str)
    raise SystemExit(CRITICAL)


def unknown(message):
    print("UNKNOWN - %s" % message)
    raise SystemExit(UNKNOWN)


def extract_dates(gtfs_path_and_file):
    """
    Check a GTFS file's calendar and calendar_dates tables.
    Return maxdate
    """
    with ZipFile(gtfs_path_and_file, mode='r') as zipfile:
        filename = None

        if 'calendar.txt' in zipfile.namelist():
            filename = 'calendar.txt'
            index = 9
        elif 'calendar_dates.txt' in zipfile.namelist():
            filename = 'calendar_dates.txt'
            index = 1

        if filename:
            with zipfile.open(filename, 'r') as calendar:
                lines = calendar.readlines()

                for line in lines[1:]:
                    # Decode line
                    line = line.decode('utf-8')
                    # Cleanup
                    line = line.replace('\n', '').replace('"', '')
                    # Split
                    split = line.split(',')

                    yield arrow.get(split[index], 'YYYYMMDD')


def expiration_date(filepath):
    return max(extract_dates(filepath))


def main():
    parser = argparse.ArgumentParser(description='GTFS plugin for NRPE.')
    parser.add_argument(
        '-w', '--warning', dest='warn', type=int, default=5,
        help='Number of days before expiration date to return a warning.'
    )
    parser.add_argument(
        '-c', '--critical', dest='crit', type=int, default=1,
        help='Number of days before expiration date to return a critical.'
    )
    parser.add_argument(
        '-d', '--directory', dest='directory',
        help='Directory to scan for GTFS files.'
    )
    parser.add_argument(
        '-p', '--pattern', dest='pattern', default='.*-gtfs.zip',
        help='Pattern of the files to read.'
    )

    parser.error = unknown

    args = parser.parse_args()

    directory = args.directory
    warn = args.warn
    crit = args.crit
    pattern = args.pattern

    p = re.compile(pattern)

    okfiles = []
    warnfiles = []
    critfiles = []

    for f in listdir(directory):
        if p.match(f):
            file = path.join(directory, f)
            date = expiration_date(path.join(file))
            datestr = date.format('YYYY-MM-DD')

            if not date:
                warnfiles.append('Date not found in file %s' % file)

            critdate = date.clone().replace(days=-crit)
            warndate = date.clone().replace(days=-warn)

            if date <= arrow.utcnow():
                critfiles.append('Files %s has expired: %s' % (file, datestr))
            if critdate <= arrow.utcnow():
                critfiles.append('File %s expires in less than %d days: %s' % (
                    file, crit, datestr
                ))
            elif warndate <= arrow.utcnow():
                warnfiles.append('File %s expires in less than %d days: %s' % (
                    file, warn, datestr
                ))
            else:
                okfiles.append('File %s expires at %s' % (file, datestr))

    message = "\n".join(critfiles + warnfiles + okfiles)

    if critfiles:
        critical(message)
    elif warnfiles:
        warning(message)
    elif okfiles:
        ok(message)
    else:
        # No file found in directory
        critical('No file matching pattern %s found in directory %s.' % (
            pattern, directory
        ))


if __name__ == '__main__':
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        traceback.print_exc()
        unknown(sys.exc_info()[1])
