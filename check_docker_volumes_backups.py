#!/usr/bin/env python3

import subprocess
import sys
import os
import re

from pathlib import Path
from datetime import datetime, timedelta

# Get volumes list
volumes = subprocess.check_output(['docker', 'volume', 'list', '-q'],
                                  stderr=subprocess.STDOUT,
                                  ).decode('utf-8').split('\n')

# Set empty lists to gather problematic backup states
warning_volumes = []
critical_volumes = []

# Set yesterday time
yesterday = datetime.now() - timedelta(days=1)

# Iterate on that list (the last one is '' so it is skipped)
for volume in volumes[:-1]:
    # Get volume backup path
    backup = Path('/var/backups/docker/volumes/%s.tar.bz2' % volume)

    # Ignore anonymous volumes
    if re.match('[a-f0-9]{64}', volume):
        continue

    # If file exists
    if backup.is_file():
        # Backup exists, is it outdated?
        mtime = datetime.fromtimestamp(os.path.getmtime(str(backup)))
        if mtime < yesterday:
            # Backup outdated, warning
            warning_volumes.append(volume)
    else:
        # Backup does not exist, critical
        critical_volumes.append(volume)

# Prepare reporting
num_volumes = len(volumes) - 1
global_status = ''
report = ''

if critical_volumes:
    global_status = 'CRITICAL'
    retcode = 2
    report = '%s volumes not backed up (%s)' % (len(critical_volumes),
                                                ' '.join(critical_volumes))

if warning_volumes:
    if not global_status:
        global_status = 'WARNING'
    retcode = 1
    report = '%s %s outdated backups (%s)' % (report,
                                              len(warning_volumes),
                                              ' '.join(warning_volumes))

if not global_status:
    global_status = 'OK'
    retcode = 0
    report = 'All %s volumes backed up' % num_volumes


# Time to report
print('%s: %s' % (global_status, report))
sys.exit(retcode)
