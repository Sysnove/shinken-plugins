#!/usr/bin/env python3

import argparse
from datetime import datetime
from urllib.error import URLError
from urllib.request import urlopen
import re
import sys

OK = 0
WARN = 1
CRIT = 2
UNKN = 3

LAST_UPDATED_RE = re.compile(
    r'(?sm:<div\s+id="last-updated".*>.*<br>\s*'
    r'([0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2} [A-Z]+)'
    r'\s*</div>)'
)


# Override ArgumentParser to exit with code 3 (UNKNOWN).
class ArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        print('%s\n' % message, file=sys.stderr)
        self.print_help(sys.stderr)

        sys.exit(UNKN)


def main():
    # Parse command line arguments
    argparser = ArgumentParser(
        description='Nominatim freshness check.'
    )

    # Get hostname on command line arguments
    # positional
    argparser.add_argument(
        'hostname',
        metavar='HOSTNAME',
        type=str,
        help='Hostname',
    )

    # Get URI on command line arguments
    # -u
    argparser.add_argument(
        '--uri', '-u',
        metavar='URI',
        type=str,
        default='/',
        help='URI to check on the server.',
    )

    # Get HTTPS on command line arguments
    # -s
    argparser.add_argument(
        '--https', '-s',
        action='store_true',
        help='Force HTTPS. Default behaviour is to try HTTP '
        'and follow redirect if any',
    )

    # Get max age thresholds on command line arguments
    # -w
    # -c
    argparser.add_argument(
        '--warning', '-w',
        type=int,
        default=150,
        help='Warning threshold, in days (default 5 months).'
    )

    argparser.add_argument(
        '--critical', '-c',
        type=int,
        default=180,
        help='Critical threshold, in days (default 6 months).'
    )

    # Parse
    args = vars(argparser.parse_args())

    # Check content
    hostname = args['hostname']
    uri = args['uri']
    force_https = args['https']
    warning = args['warning']
    critical = args['critical']

    # Get content
    if force_https:
        scheme = "https"
    else:
        scheme = "http"

    url = f"{scheme}://{hostname}{uri}"

    try:
        with urlopen(url) as f:
            if f.status != 200:
                print(f"CRITICAL: Code {f.status} returned instead of 200.")
                sys.exit(CRIT)

            output = f.read().decode('UTF-8')
    except URLError as e:
        print(
            f"ERROR: impossible to connect to {url}:\n{e.reason}",
            file=sys.stderr
        )
        sys.exit(UNKN)

    # Parse content to get last updated date
    m = LAST_UPDATED_RE.search(output)
    if not m:
        print("ERROR: Last updated date not found.")
        sys.exit(CRIT)

    # Compare with thresholds
    now = datetime.now()
    last_updated = datetime.strptime(m.group(1), '%Y/%m/%d %H:%M %Z')

    age = now - last_updated
    if age.days > critical:
        print(f'CRITICAL: Data is more than {critical} days old: {age.days}')
        sys.exit(CRIT)

    if age.days > warning:
        print(f'WARNING: Data is more than {warning} days old: {age.days}')
        sys.exit(WARN)

    print(f"OK: Data is {age.days} old.")
    sys.exit(OK)


if __name__ == '__main__':
    main()
