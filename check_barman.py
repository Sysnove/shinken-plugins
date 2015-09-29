#!/usr/bin/env python

#
# Alexis Lahouze, Sysnove, 2014
#
# Description :
#
# This plugin checks some indicators in barman.
#
# Copyright 2014 Alexis Lahouze <alexis@sysnove.fr>
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more
# details.
#

from __future__ import print_function

from datetime import datetime
import argparse
import dateutil
import os
import pwd
import sys

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3


def print_message(message, perfdata_str=None):
    if perfdata_str is not None:
        print("%s | %s" % (message, perfdata_str))
    else:
        print(message)


def get_perfdata_str(perfdata_key, perfdata_value,
                     perfdata_warn, perfdata_crit,
                     perfdata_min, perfdata_max):

    if perfdata_key is not None:
        warn_str = str(perfdata_warn) if perfdata_warn is not None else ''
        crit_str = str(perfdata_crit) if perfdata_crit is not None else ''
        min_str = str(perfdata_min) if perfdata_min is not None else ''
        max_str = str(perfdata_max) if perfdata_max is not None else ''

        perfdata_str = "%s=%s;%s;%s;%s;%s" % (perfdata_key, perfdata_value,
                                              warn_str, crit_str, min_str,
                                              max_str)

        return perfdata_str
    else:
        return None


def ok(message, perfdata_str=None):
    print_message("OK - %s" % (message), perfdata_str)
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


def exit_check(value, warn, crit, message, under=False, message_ok=None,
               perfdata_key=None, perfdata_min=None, perfdata_max=None):

    if message_ok is None:
        message_ok = message

    comparison = max
    if under:
        comparison = min

    perfdata = None
    if perfdata_key is not None:
        perfdata = get_perfdata_str(perfdata_key, value, warn, crit,
                                    perfdata_min, perfdata_max)

    if crit is not None and comparison(value, crit) == value:
        critical(message, perfdata)

    if warn is not None and comparison(value, warn) == value:
        warning(message, perfdata)

    ok(message_ok, get_perfdata_str(perfdata_key, value, warn, crit,
                                    perfdata_min, perfdata_max))


def get_milliseconds(timedelta):
    milliseconds = float(timedelta.microseconds) / 1000
    milliseconds = milliseconds + float(timedelta.seconds) * 1000
    return milliseconds


def timed(function, *args, **kwargs):
    start = datetime.now()
    retval = function(*args, **kwargs)
    end = datetime.now()
    return (retval, end - start)


def ssh(server, args):
    warn = args.warning
    crit = args.critical

    from barman.backup_executor import _parse_ssh_command
    from barman.command_wrappers import Command

    ssh_command, ssh_options = _parse_ssh_command(server.config.ssh_command)
    cmd = Command(ssh_command, ssh_options)

    (retval, duration) = timed(cmd, 'true')
    milliseconds = get_milliseconds(duration)
    perfdata_key = "milliseconds"

    if retval == 0:
        exit_check(milliseconds, warn, crit, "SSH command ran in %sms" %
                   (milliseconds), perfdata_key=perfdata_key, perfdata_min=0)
    else:
        critical("Impossible to run a SSH command.",
                 get_perfdata_str(perfdata_key, milliseconds, warn, crit, 0,
                                  None))


def postgresql(server, args):
    warn = args.warning
    crit = args.critical

    (remote_status, duration) = timed(server.get_remote_status)

    milliseconds = get_milliseconds(duration)
    perfdata_key = "milliseconds"

    perfdata_str = get_perfdata_str(perfdata_key, milliseconds, warn, crit, 0,
                                    None)

    if not remote_status['server_txt_version']:
        critical("Impossible to join PostgreSQL server.", perfdata_str)

    if server.config.backup_options == 'concurrent_backup':
        if not remote_status['pgespresso_installed']:
            critical("pgespresso extension must be installed.", perfdata_str)

    if remote_status['archive_mode'] != 'on':
        critical("Server archive mode is not set.", perfdata_str)

    if not remote_status['archive_command'] or \
            remote_status['archive_command'] == '(disabled)':
        critical("Archive command must be set.", perfdata_str)

    version = remote_status['server_txt_version']

    exit_check(milliseconds, warn, crit,
               "PostgreSQL server %s is well configured." % version,
               perfdata_key=perfdata_key, perfdata_min=0)


def backups_available(server, args):
    warn = args.warning
    crit = args.critical

    from barman.infofile import BackupInfo
    status_filter = BackupInfo.STATUS_NOT_EMPTY

    backups = server.get_available_backups(status_filter)
    nb_backups = len(backups)

    exit_check(nb_backups, warn, crit,
               "Only %d backups available." % nb_backups,
               under=True, message_ok="%d backups available" % nb_backups,
               perfdata_key="backups", perfdata_min=0)


def last_backup_age(server, args):
    warn = args.warning
    crit = args.critical

    from barman.infofile import BackupInfo

    backup_id = server.get_last_backup()

    status_filter = BackupInfo.STATUS_NOT_EMPTY
    backups = server.get_available_backups(status_filter)

    backup = backups[backup_id]
    begin_time = backup.begin_time
    now = datetime.now().replace(tzinfo=dateutil.tz.tzlocal())

    age = now - begin_time

    hours = age.days * 24 + age.seconds / 3600

    exit_check(hours, warn, crit, "Last backup is %s hours old." % hours,
               perfdata_key="hours", perfdata_min=0)


def last_wal_age(server, args):
    warn = args.warning
    crit = args.critical

    from barman.infofile import WalFileInfo

    with server.xlogdb() as fxlogdb:
        line = None
        for line in fxlogdb:
            pass

        if line is None:
            critical("No WAL received yet.")

    #name, size, time, compression = server.xlogdb_parse_line(line)
    wal_info = WalFileInfo.from_xlogdb_line(line)

    time = datetime.fromtimestamp(wal_info.time)
    now = datetime.now()

    age = now - time
    minutes = age.seconds / 60
    minutes = minutes + age.days * 60 * 24

    exit_check(minutes, warn, crit, "Last WAL is %s minutes old." % minutes,
               perfdata_key="minutes", perfdata_min=0)


def failed_backups(server, args):
    warn = args.warning
    crit = args.critical

    from barman.infofile import BackupInfo
    status_filter = BackupInfo.FAILED

    backups = server.get_available_backups(status_filter)
    nb_backups = len(backups)

    exit_check(nb_backups, warn, crit, "%d backups failed." % nb_backups,
               perfdata_key="backups", perfdata_min=0)


def missing_wals(server, args):
    warn = args.warning
    crit = args.critical

    from barman.xlog import is_wal_file
    from barman.infofile import WalFileInfo

    wals_directory = server.config.wals_directory

    missing_wals = 0
    with server.xlogdb() as fxlogdb:
        for line in fxlogdb:
            #name, size, time, compression = server.xlogdb_parse_line(line)
            wal_info = WalFileInfo.from_xlogdb_line(line)
            name = wal_info.name

            directory = name[0:16]

            if is_wal_file(name):
                file_path = os.path.join(wals_directory, directory, name)
                if not os.path.exists(file_path):
                    missing_wals = missing_wals + 1

    exit_check(missing_wals, warn, crit,
               "There are %d missing wals for the last backup." % missing_wals,
               perfdata_key="missing", perfdata_min=0)


ACTIONS = {
    "ssh": (ssh, "SSH connection. Thresholds are in milliseconds."),
    "postgresql": (postgresql,
                   "PostgreSQL connection. Thresholds are in milliseconds."),
    "backups_available": (backups_available,
                          "Available backups. Thresholds are counts."),
    "last_backup_age": (last_backup_age,
                        "Last backup age. Thresholds are in days."),
    "last_wal_age": (last_wal_age, "Last WAL age. Thresholds are in minutes."),
    "failed_backups": (failed_backups,
                       "Failed backups. Thresholds are counts."),
    "missing_wals": (missing_wals, "Missing WALs. Threshold are counts."),
}


def main():
    parser = argparse.ArgumentParser(description="Barman plugin for NRPE.")
    parser.add_argument("-s", "--server", dest="server",
                        help="server to check")
    parser.add_argument('-w', '--warning', type=int, dest="warning",
                        metavar="W", help="warning threshold.")
    parser.add_argument('-c', '--critical', type=int, dest="critical",
                        metavar="C", help="critical threshold.")
    parser.add_argument('-u' '--user', dest='user', metavar='U',
                        help="user needed to run this script. If the "
                        "current user is not this one, the script will try " +
                        "to rerun itself using sudo.")

    subparsers = parser.add_subparsers()

    for key, value in ACTIONS.items():
        (action, help) = value
        subparser = subparsers.add_parser(key, help=help)
        subparser.set_defaults(action=action)

    parser.error = unknown

    args = parser.parse_args()

    user = pwd.getpwuid(os.getuid())[0]

    if args.user and user != args.user:
        import subprocess

        retval = subprocess.call(["/usr/bin/sudo", "-u", args.user] + sys.argv)
        raise SystemExit(retval)

    from barman.config import Config
    from barman.server import Server

    config = Config()
    config.load_configuration_files_directory()
    server = Server(config.get_server(args.server))

    try:
        args.action(server, args)
    except KeyError:
        unknown("The action %s does not exist." % args.action)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except:
        # Return UNKNOWN code if exception is catched.
        unknown(sys.exc_info()[1])
