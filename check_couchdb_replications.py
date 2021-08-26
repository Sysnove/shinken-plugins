#!/usr/bin/env python2
'''Check to make sure that all the replications on the local CouchDB server
are actually running.'''

# Note : Imported from https://gist.github.com/mastbaum/cc6d23f98ad6d1289907

import argparse
from datetime import datetime, timedelta
from operator import itemgetter
import requests
import sys
import tempfile

# Nagios status codes
OK, WARNING, CRITICAL, UNKNOWN = range(4)

def main(host, replicator, replication, auth, age_timeout):
    headers = {
        'Content-type': 'application/json'
    }

    if auth:
        headers['Authorization'] = 'Basic %s' % auth.encode('base64').rstrip()

    # Query the server and parse into objects
    try:
        replicator_url = host + replicator + '/_all_docs?include_docs=true'
        replications = requests.get(replicator_url, headers=headers)
        active_tasks = requests.get(host + '/_active_tasks', headers=headers)
    except Exception:
        print 'REPLICATION STATUS UNKNOWN - Error connecting to server'
        return UNKNOWN

    if replications.status_code >= 400:
        print 'REPLICATION STATUS UNKNOWN - Error connecting to server (HTTP %i)' % replications.status_code
        return UNKNOWN

    if active_tasks.status_code >= 400:
        print 'REPLICATION STATUS UNKNOWN - Error connecting to server (HTTP %i)' % replications.status_code
        return UNKNOWN

    reps = filter(lambda x: 'source' in x, [x['doc'] for x in replications.json()['rows']])
    reps = sorted(reps, key=itemgetter('source'))

    if replication is not None:
        reps = [r for r in reps if r['_id'] == replication]

    tasks = {}
    for at in active_tasks.json():
        rep_id = at.get('replication_id', '')
        if '+' in rep_id:
            r_id = rep_id.split('+')[0]
        else:
            r_id = rep_id
        tasks[r_id] = at

    # Merge and check
    status = OK
    problems = []
    for rep in reps:
        if '_replication_id' in rep:
	    task = tasks.get(rep['_replication_id'])
	    if task:
	        rep.update(task)

        doc_id = rep['_id']
        rep_state = rep.get('_replication_state', 'N/A')
        reason = rep.get('_replication_state_reason', '')
        updated = rep.get('updated_on', 0)
        age = datetime.now() - datetime.fromtimestamp(updated)

        rep_problems = {}

        # Check that all replications are in the triggered state
        if rep_state != 'triggered':
            rep_problems['state'] = rep_state
            if reason:
                rep_problems['state'] += ', ' + reason
            status = CRITICAL

        # Check that all replications have updated recently
        if age > timedelta(seconds=age_timeout):
            if updated > 0:
                rep_problems['age'] = str(age)
            else:
                rep_problems['age'] = 'infinity'
            status = max(status, WARNING)

        if len(rep_problems) > 0:
            problem_list = []
            for k, v in rep_problems.items():
                problem_list.append('%s: %s' % (k, v))
            problems.append('%s (%s)' % (doc_id, '; '.join(problem_list)))

    # Build the output string
    if status == OK:
        s = 'OK'
    elif status == WARNING:
        s = 'WARNING'
    elif status == CRITICAL:
        s = 'CRITICAL'
    else:
        s = 'UNKNOWN'

    if replication is None:
        output = 'REPLICATION STATUS %s - %i replications, %i problems' % (s, len(reps), len(problems))
    else:
        if not reps:
            status = CRITICAL
            output = 'REPLICATION STATUS CRITICAL - Replication %s not found' % replication
        else:
            output = 'REPLICATION STATUS %s - Replication %s is %s' % (s, replication, s)

    if len(problems) > 0:
        output += ': ' + ', '.join(problems)

    print output
    return status


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', '-s', default='http://localhost:5984')
    parser.add_argument('--replicator', '-d', default='/_replicator')
    parser.add_argument('--age-timeout', '-t', default=120,
                        help='Warning time for stale replications, in s')
    parser.add_argument('--auth', '-a',
                        help='Basic HTTP authentication string as "username:password"')
    parser.add_argument('--replication', '-r', default=None)
    args = parser.parse_args()

    try:
        status = main(args.host, args.replicator, args.replication, args.auth, args.age_timeout)
    except Exception as e:
        print 'REPLICATION STATUS UNKNOWN - Python exception %s' % str(e)
        status = UNKNOWN

    sys.exit(status)
