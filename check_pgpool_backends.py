#!/usr/bin/env python3

from subprocess import run, PIPE, STDOUT
from sys import exit, stderr

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

def main():
    # pcp_node_info
    status = run(
        ['/usr/sbin/pcp_node_info', '-h', 'localhost', '-U', 'pgpool', '--no-password'],
        stdout=PIPE, stderr=STDOUT
    )

    # By convention, may be passed as argmument.
    nominal_primary_id = 0

    # Command failed, this is not expected.
    if status.returncode != 0:
        print(f"UNKONWN {status.stdout}")
        print(f"  In case of auth problem, please check {os.environ['HOME']}/.pcppass."
        exit(UNKNOWN)

    # Warning and Critical messages.
    warning=list()
    critical=list()

    # In PGPool node id begins at 0.
    node_id=0
    primary_found=False

    # One line per backend
    for line in status.stdout.decode('utf-8').splitlines():
        # Retrieve backend information
        (hostname, port, status, lb_weight, status_name, status_actual, backend_role, backend_role_actual, replication_delay, replication_state, replication_type, status_change_date, status_change_time) = line.split(' ')

        # Some debugging
        print(f"DEBUG #{node_id} {hostname}:{port} ({backend_role_actual})", file=stderr)

        # Check for node status:
        #   0. Initializing
        #   1. Node is up, no connections
        #   2. Node is up, connections are pooled
        #   3. Node is down
        if status == '3':
            # Nominal primary is down.
            if node_id == nominal_primary_id:
                critical.append(f"Nominal primary node #{node_id} is down.")
            elif backend_role_actual == "primary":
                critical.append(f"Primary #{node_id} is down.")
            else:
                warning.append(f"Secondary #{node_id} is down.")
        else:
            # Check for number of primaries
            if backend_role_actual == "primary":
                if primary_found:
                    critical.append(f"Found two active primaries")

                primary_found = True

                # Warning if primary is not the nominal one.
                # This situation does not need to reclone the nominal primary.
                if nominal_primary_id != node_id:
                    critical.append(f"Node #{node_id} is primary instead of node #{nominal_primary_id}.")

                # Check replication lag.
                if int(replication_delay) > 10:
                    warning.append(f"Node #{node_id} has a high lag."

        # Check backend role consistency.
        if backend_role != backend_role_actual:
            warning.append(f"Real backend role for node #{node_id} is not consistent.")

        # Increment node id.
        node_id+=1

    # No primary found.
    if not primary_found:
        critical.append("No primary found in cluster.")

    for msg in critical:
        print(f"CRITICAL {msg}")

    for msg in warning:
        print(f"WARNING {msg}")

    if critical:
        exit(CRITICAL)

    if warning:
        exit(WARNING)

    print("OK Cluster is fully operational.")
    exit(OK)

if __name__ == '__main__':
    main()
