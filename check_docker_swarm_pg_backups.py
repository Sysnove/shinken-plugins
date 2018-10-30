#!/usr/bin/env python3

import subprocess
import sys
import os

from pathlib import Path
from datetime import datetime, timedelta

# Get services ant databases list
databases = subprocess.check_output(['docker_swarm_pg_list_db.sh'],
                                    stderr=subprocess.DEVNULL,
                                    ).decode('utf-8').split('\n')
# Set empty lists to gather problematic backup states
warning_databases = []
critical_databases = []

# Set yesterday time
yesterday = datetime.now() - timedelta(days=1)

# Iterate on that list (the last one is '' so it is skipped)
for item in databases[:-1]:
    # item is "service:database"
    service, database = item.split(':')

    # Get postgres backup path
    backup = Path('/var/backups/docker-postgres/%s/%s.pg_dump.gz' %
                  (service, database))

    # If file exists
    if backup.is_file():
        # Backup exists, is it outdated?
        mtime = datetime.fromtimestamp(os.path.getmtime(str(backup)))
        if mtime < yesterday:
            # Backup outdated, warning
            warning_databases.append(item)
    else:
        # Backup does not exist, critical
        critical_databases.append(item)

# Prepare reporting
num_databases = len(databases) - 1
global_status = ''
report = ''

if critical_databases:
    global_status = 'CRITICAL'
    retcode = 2
    report = '%s databases not backed up (%s)' % (len(critical_databases),
                                                  ' '.join(critical_databases))

if warning_databases:
    if not global_status:
        global_status = 'WARNING'
    retcode = 1
    report = '%s %s outdated backups (%s)' % (report,
                                              len(warning_databases),
                                              ' '.join(warning_databases))

if not global_status:
    global_status = 'OK'
    retcode = 0
    report = 'All %s pg databases backed up' % num_databases


# Time to report
print('%s: %s' % (global_status, report))
sys.exit(retcode)
