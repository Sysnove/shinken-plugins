#!/bin/bash
#
# Event handler script for running maldet-scan when maldet turns unknown
#

function try_to_fix {
    echo -n "Rescan maldet"
    sudo /usr/local/bin/maldet-scan
}

# What state is the service in?
case "$1" in
OK)
  # The service just came back up, so don't do anything…
  ;;
WARNING)
  # We don't really care about warning states, since the service is probably still running…
  ;;
UNKNOWN)
  # We don't know what might be causing an unknown error, so don't do anything…
  if [ "$2" = "HARD" ]; then
      try_to_fix
  fi
  ;;
CRITICAL)
  # Aha!  The service appears to have a problem - perhaps we should restart the server…
  # Is this a "soft" or a "hard" state?
  case "$2" in

    # We're in a "soft" state, meaning that Nagios is in the middle of retrying the
    # check before it turns into a "hard" state and contacts get notified…
    SOFT)

    # What check attempt are we on? We don't want to trigger anything on first check, because it may just be a fluke!
      case "$3" in
        2)
          # try_to_fix
          ;;
        esac
        ;;

    HARD)
      try_to_fix
      ;;
    esac
    ;;
  esac
exit 0
