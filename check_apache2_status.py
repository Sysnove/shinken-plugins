#!/usr/bin/env python3
#
#         DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                 Version 2, December 2004
#
# Copyright 2014 - Guillaume Subiron (Sysnove)
#
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
#         DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
# TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.
#
# -*- coding: utf-8 -*-
# vim: ai ts=4 sts=4 et sw=4 nu


import argparse
import requests
import time
import json
import re

TMP_FILE = "/var/tmp/nagios_check_apache2_status_last_run"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-H", "--hostname", default="localhost")
    parser.add_argument("-P", "--port", default=80)
    parser.add_argument("-S", "--ssl", nargs="?", default=False, const=True)
    parser.add_argument("-s", "--status-page", default="server-status")
    parser.add_argument("-w", "--total-warning", default=80, type=int)
    args = parser.parse_args()

    scheme = "https" if args.ssl else "http"

    url = "%s://%s:%s/%s?auto" % (scheme, args.hostname, args.port, args.status_page)

    try:
        r = requests.get(url)
    except:
        print("UNKNOWN - Error requesting %s" % url)
        raise SystemExit(3)

    if r.status_code != 200:
        print("CRITICAL - %s", r.status_code)
        raise SystemExit(2)

    values = dict()
    for line in r.text.splitlines():
        values[line.split(":")[0]] = " ".join(line.split(":")[1:]).strip()

    for k, v in values.items():
        try:
            values[k] = int(v)
        except:
            pass

    try:
        version = values["ServerVersion"].split(" ")[0]
    except KeyError:
        version = "Apache2"

    values["MaxWorkers"] = len(values["Scoreboard"])
    values["WarnWorkers"] = int(values["MaxWorkers"] * (args.total_warning / 100.0))

    values["TotalWorkers"] = values["IdleWorkers"] + values["BusyWorkers"]

    now = int(time.time())

    try:
        last_check = json.load(open(TMP_FILE))
    except:
        print("UNKNOWN - %s does not exist, please run the check again." % TMP_FILE)
        raise SystemExit(3)
    finally:
        json.dump((now, values["Total Accesses"]), open(TMP_FILE, "w"))

    values["ReqPerSec"] = "%.2f" % round(
        (values["Total Accesses"] - last_check[1]) / (now - last_check[0]), 2
    )

    perfdata = (
        "Uptime: %(Uptime)s, ReqPerSec: %(ReqPerSec)s, BytesPerSec: %(BytesPerSec)s, Workers: %(TotalWorkers)s (Busy: %(BusyWorkers)s, Idle: %(IdleWorkers)s)|Uptime=%(Uptime)ss; ReqPerSec=%(ReqPerSec)s; BytesPerSec=%(BytesPerSec)s; BusyWorkers=%(BusyWorkers)s:%(WarnWorkers)s:%(MaxWorkers)s; IdleWorkers=%(IdleWorkers)s;"
        % values
    )

    if values["IdleWorkers"] < 2:
        print("%s WARNING (IdleWorkers < 2) - %s" % (version, perfdata))
        raise SystemExit(1)
    if values["TotalWorkers"] >= values["WarnWorkers"]:
        print(
            "%s WARNING (TotalWorkers > WarnWorkers=%s) - %s"
            % (version, values["WarnWorkers"], perfdata)
        )
        raise SystemExit(1)
    if values["TotalWorkers"] >= values["MaxWorkers"]:
        print(
            "%s WARNING (TotalWorkers > MaxWorkers=%s) - %s"
            % (version, values["MaxWorkers"], perfdata)
        )
        raise SystemExit(1)
    else:
        print("%s OK - %s" % (version, perfdata))


if __name__ == "__main__":
    main()
