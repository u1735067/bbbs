#!/usr/bin/env bash
if [ $# -lt 2 ]; then
  echo "usage: [-s|--socket] uds-target.sock | [-t|--tcp] port"
elif [ "$1" == '-s' -o "$1" == '--socket' ]; then
  exec socat STDIO UNIX-CONNECT:"$2"
elif [ "$1" == '-t' -o "$1" == '--tcp' ]; then
  host=localhost
  #if [ $# -eq 3 -a -n "$3"  ]; then
  #  host="$3"
  #fi
  exec socat STDIO TCP-CONNECT:"$host":"$2"
else
  echo "unknown method"
fi