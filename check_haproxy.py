#!/usr/bin/env python3
"""
###############################################################################
# check_haproxy.py
# Icinga/Nagios plugin that checks the metrics of a HAProxy load balancer
#
# Author        : Mauno Erhardt <mauno.erhardt@burkert.com>
# Copyright     : (c) 2022 Burkert Fluid Control Systems
# Source        : https://github.com/m-erhardt/check-haproxy
# License       : GPLv3 (http://www.gnu.org/licenses/gpl-3.0.txt)
#
###############################################################################
"""

import sys
import socket
import time
from argparse import ArgumentParser, Namespace as Arguments
import argparse


class HaproxyFrontend:
    """ Class for haproxy frontend object """
    # pylint: disable=too-few-public-methods

    def __init__(self):
        self.name: str = None
        self.state: str = None
        self.sessions: int = None
        self.sessionlimit: int = None
        self.bytein: int = None
        self.byteout: int = None


class HaproxyBackend:
    """ Class for haproxy backend object """
    # pylint: disable=too-few-public-methods

    def __init__(self):
        self.name: str = None
        self.state: str = None
        self.sessions: int = None
        self.sessionlimit: int = None
        self.bytein: int = None
        self.byteout: int = None


class HaproxyServer:
    """ Class for haproxy server object """
    # pylint: disable=too-few-public-methods,too-many-instance-attributes

    def __init__(self):
        self.name: str = None
        self.backend: str = None
        self.state: str = None
        self.sessions: int = None
        self.sessionlimit: int = None
        self.sessionstotal: int = None
        self.queue: int = None
        self.bytein: int = None
        self.byteout: int = None


def get_args():
    """ Parse Arguments """
    parser = ArgumentParser(description="Icinga/Nagios plugin which checks a haproxy load balancer")

    parser.add_argument("--socketfile", required=False,
                        help="Location of haproxy stats socket file",
                        type=str, dest='socketfile',
                        default="/run/haproxy/admin.sock")
    parser.add_argument("--mode", required=False, type=str, dest="mode",
                        default="instance", choices=["instance", "frontend"],
                        help="Plugin mode")
    parser.add_argument("--perfdata", action=argparse.BooleanOptionalAction,
                        help="Enable/Disable perfdata")

    thresholds = parser.add_argument_group('Thresholds')
    thresholds.add_argument("--slimwarn", required=False,
                            help="Exit WARN if sessions reach <slimwarn>%% of session limit",
                            type=int, dest='slim_warn', default=80)
    thresholds.add_argument("--slimcrit", required=False,
                            help="Exit CRIT if sessions reach <slimcrit>%% of session limit",
                            type=int, dest='slim_crit', default=90)

    modeargs = parser.add_argument_group('Mode-specific arguments')
    modeargs.add_argument("--frontend", required=False, default=None,
                          help="Name of frontend to check (only with \"--mode frontend\")",
                          type=str, dest="frontend")

    args = parser.parse_args()

    # Validate arguments
    if args.frontend is not None and args.mode != "frontend":
        exit_plugin(3, '--frontend only works with --mode frontend', '')

    if (args.slim_warn is not None
            and args.slim_crit is not None
            and args.slim_warn > args.slim_crit):
        exit_plugin(3, '--slimcrit must be higher than --slimwarn', '')

    return args


def exit_plugin(returncode: int, output: str, perfdata: str):
    """ Check status and exit accordingly """
    if returncode == 3:
        print("UNKNOWN - " + str(output))
        sys.exit(3)
    if returncode == 2:
        print("CRITICAL - " + str(output) + str(perfdata))
        sys.exit(2)
    if returncode == 1:
        print("WARNING - " + str(output) + str(perfdata))
        sys.exit(1)
    elif returncode == 0:
        print("OK - " + str(output) + str(perfdata))
        sys.exit(0)


def set_state(newstate: int, state: int):
    """ Set return state of plugin """

    if (newstate == 2) or (state == 2):
        returnstate = 2
    elif (newstate == 1) and (state not in [2]):
        returnstate = 1
    elif (newstate == 3) and (state not in [1, 2]):
        returnstate = 3
    else:
        returnstate = 0

    return returnstate


def haproxy_cmd(cmd: str, socketfile: str):
    """ send cmd to haproxy socket and return reply as str """

    try:
        # Open connection to haproxy socket
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(socketfile)

        # Send command
        sock.sendall(cmd.encode("ascii"))
        time.sleep(0.1)

        # Shut down sending
        sock.shutdown(socket.SHUT_WR)

        # Create buffer for receiving
        buf = ""

        while True:
            # Write reply to buffer in chunks of 1024 bytes
            data = sock.recv(1024)
            if not data:
                break
            buf += data.decode()

        # Close socket connection
        sock.close()

    except FileNotFoundError:
        exit_plugin(3, f'Socket file { socketfile } not found!', "")
    except PermissionError:
        exit_plugin(3, f'Access to socket file { socketfile } denied!', "")
    except TimeoutError:
        exit_plugin(3, f'Connection to socket { socketfile } timed out!', "")
    except ConnectionError as err:
        exit_plugin(3, f'Error during socket connection: { err }', "")

    return buf


def get_haproxy_stats(socketfile: str):
    """ Execute haproxy "show stat" command and return reply as dict """

    resp = haproxy_cmd("show stat \n ", socketfile)

    # Initialize return object
    stats = {}

    # Extract column names from first line
    stats["columns"] = resp.splitlines()[0].split(",")

    # Initiate list for rows
    stats["values"] = []

    # Write values to dict
    for line in resp.splitlines()[1:]:
        if line != "":
            stats["values"].append(line.split(","))

    # Initiate lists for objects of type HaproxyFrontend, HaproxyBackend and HaproxyServer
    frontends = []
    backends = []
    servers = []

    # Get column numbers of values
    col_nr = {}
    for item in ['# pxname', 'svname', 'status', 'scur', 'slim', 'stot', 'qcur', 'bin', 'bout']:
        col_nr[item] = stats["columns"].index(item)

    # Loop through returned rows
    for row in stats["values"]:

        if row[col_nr['svname']] == "FRONTEND":
            obj = HaproxyFrontend()
            obj.name = row[col_nr['# pxname']]
            obj.state = row[col_nr['status']]
            obj.sessions = int(row[col_nr['scur']])
            obj.bytein = int(row[col_nr['bin']])
            obj.byteout = int(row[col_nr['bout']])
            try:
                obj.sessionlimit = int(row[col_nr['slim']])
            except ValueError:
                obj.sessionlimit = None

            frontends.append(obj)

        elif row[col_nr['svname']] == "BACKEND":
            obj = HaproxyBackend()
            obj.name = row[col_nr['# pxname']]
            obj.state = row[col_nr['status']]
            obj.sessions = int(row[col_nr['scur']])
            obj.bytein = int(row[col_nr['bin']])
            obj.byteout = int(row[col_nr['bout']])
            try:
                obj.sessionlimit = int(row[col_nr['slim']])
            except ValueError:
                obj.sessionlimit = None

            backends.append(obj)

        else:
            obj = HaproxyServer()
            obj.name = row[col_nr['svname']]
            obj.state = row[col_nr['status']]
            obj.sessions = int(row[col_nr['scur']])
            obj.bytein = int(row[col_nr['bin']])
            obj.byteout = int(row[col_nr['bout']])
            try:
                obj.sessionlimit = int(row[col_nr['slim']])
            except ValueError:
                obj.sessionlimit = None
            obj.sessionstotal = int(row[col_nr['stot']])
            obj.queue = int(row[col_nr['qcur']])

            servers.append(obj)

    return frontends, backends, servers


def check_instance(frontends: list, backends: list, servers: list, args: Arguments):
    """ Check HAproxy instance """
    # pylint: disable=too-many-locals,too-many-branches,too-many-statements

    # Initialize state and output string
    output = ""
    state = 0

    output += (f'haproxy running with { len(frontends) } frontends, { len(backends) } backends, '
               f'{ len(servers) } servers ')

    # Calculate total sessions
    sessions = {'server_current': 0, 'server_total': 0, 'frontend_current': 0, 'backend_current': 0}
    queues = {'server_current': 0}
    errors = []

    # Loop through server objects
    for server in servers:
        sessions["server_current"] += server.sessions
        sessions["server_total"] += server.sessionstotal
        queues["server_current"] += server.queue
        if server.state not in ["UP", 'no check'] and not server.state.startswith('UP'):
            errors.append(f'Warn: server { server.name } is { server.state }')
            state = set_state(1, state)

        if server.sessionlimit is not None:
            # Calculate session thresholds for server
            wthres = server.sessionlimit * (args.slim_warn / 100)
            cthres = server.sessionlimit * (args.slim_crit / 100)

            if (server.sessions >= wthres) and (server.sessions < cthres):
                errors.append(f'Warn: server { server.name } is using { server.sessions }/{ server.sessionlimit } sessions')
                state = set_state(1, state)

            if server.sessions >= cthres:
                errors.append(f'Crit: server { server.name } is using { server.sessions }/{ server.sessionlimit } sessions')
                state = set_state(2, state)

    output += f'and { sessions["server_current"] } sessions'

    # Loop through frontend objects
    for frontend in frontends:
        sessions["frontend_current"] += frontend.sessions

        if frontend.state != "OPEN":
            errors.append(f'Warn: frontend { frontend.name } is { frontend.state }')
            state = set_state(1, state)

        if frontend.sessionlimit is not None:
            wthres = frontend.sessionlimit * (args.slim_warn / 100)
            cthres = frontend.sessionlimit * (args.slim_crit / 100)

            if (frontend.sessions >= wthres) and (frontend.sessions < cthres):
                errors.append(f'Warn: frontend { frontend.name } is using { frontend.sessions }/{ frontend.sessionlimit } sessions')
                state = set_state(1, state)

            if frontend.sessions >= cthres:
                errors.append(f'Crit: frontend { frontend.name } is using { frontend.sessions }/{ frontend.sessionlimit } sessions')
                state = set_state(2, state)

    # Loop through backend objects
    for backend in backends:
        sessions["backend_current"] += backend.sessions

        if backend.state != "UP":
            errors.append(f'Warn: backend { backend.name } is { backend.state }')
            state = set_state(1, state)

        if backend.sessionlimit is not None:
            wthres = backend.sessionlimit * (args.slim_warn / 100)
            cthres = backend.sessionlimit * (args.slim_crit / 100)

            if (backend.sessions >= wthres) and (backend.sessions < cthres):
                errors.append(f'Warn: backend { backend.name } is using { backend.sessions }/{ backend.sessionlimit } sessions')
                state = set_state(1, state)

            if backend.sessions >= cthres:
                errors.append(f'Crit: backend { backend.name } is using { backend.sessions }/{ backend.sessionlimit } sessions')
                state = set_state(2, state)

    output = f'{", ".join(errors + [output])}'

    if args.perfdata:
        perfdata = (f' | \'sessions\'={ sessions["server_current"] };;;; '
                    f'\'sessions_total\'={ sessions["server_total"] };;;; '
                    f'\'frontends\'={ len(frontends) };;;; '
                    f'\'backends\'={ len(backends) };;;; '
                    f'\'servers\'={ len(servers) };;;; ')
    else:
        perfdata = ''

    exit_plugin(state, output, perfdata)


def check_frontend(frontends: list, args: Arguments):
    """ Check single HAproxy frontend """

    frontend = None

    # Extract only the frontend we want to check
    for item in frontends:
        if item.name == args.frontend:
            frontend = item
            break

    if frontend is None:
        exit_plugin(3, f'Unable to find frontend { args.frontend }', '')

    # Calculate absolute WARN and CRIT thresholds for frontend
    if frontend.sessionlimit is not None:
        wthres = frontend.sessionlimit * (args.slim_warn / 100)
        cthres = frontend.sessionlimit * (args.slim_crit / 100)

    if args.perfdata:
        perfdata = (f' | \'sessions\'={ frontend.sessions }'
                    f';{ wthres or "" };{ cthres or "" };0;{ frontend.sessionlimit or "" } '
                    f'\'bytein\'={ frontend.bytein }B;;;; '
                    f'\'byteout\'={ frontend.byteout }B;;;;')
    else:
        perfdata = ''

    output = (f'HAProxy frontend { frontend.name } is { frontend.state }, '
              f'Sessions: { frontend.sessions }/{ frontend.sessionlimit or "-" }')

    if frontend.state != "OPEN":
        # Frontend is not OPEN, exit critical

        exit_plugin(2, output, perfdata)

    elif frontend.sessions >= cthres:
        # Frontend sesions above CRIT threshold

        exit_plugin(2, output, perfdata)

    elif frontend.sessions >= wthres:
        # Frontend sesions above WARN threshold

        exit_plugin(1, output, perfdata)

    else:
        # Everything OK
        exit_plugin(0, output, perfdata)


def main():
    """ Main program code """

    # Get Arguments
    args = get_args()

    frontends, backends, servers = get_haproxy_stats(args.socketfile)

    if args.mode == "frontend":
        check_frontend(frontends, args)

    elif args.mode == "instance":
        check_instance(frontends, backends, servers, args)

    else:
        exit_plugin(3, 'Unknown plugin mode', '')


if __name__ == "__main__":
    main()
