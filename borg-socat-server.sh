#!/usr/bin/env bash

#BORG_BASE_DIR=/var/lib/borg
#BORG_CONFIG_DIR=/var/lib/borg/config
#BORG_SECURITY_DIR=/var/lib/borg/security
#BORG_KEYS_DIR=/var/lib/borg/keys
#BORG_CACHE_DIR=/srv/borg/.borg_cache
if [ $# -lt 3 ]; then
  echo "usage: [-s|--socket] local-listening-uds.sock remote-connecting-uds.sock target-wrapper host <borg command>"
  echo "usage: [-t|--tcp] local-listening-port remote-connecting-port target-wrapper host <borg command>"
  echo "example: $0 -s /tmp/local.sock /tmp/remote.sock /root/borg-socat-client.sh important-server /root/borg create ssh://server/path/to/repo::{hostname}-{utcnow} path to backup"
#SSH_ARGS
#BORGW_RESTRICT_PATH
#BORGW_RESTRICT_REPOSITORY
#BORGW_APPEND_ONLY
#BORGW_STORAGE_QUOTA
else
  print_args() {
    # Test space quoting
    python -c "import sys; print(sys.argv[1:])" "$@"
  }

  borg_serve_cmd="./borg serve --umask 077"
  if [ "$BORGW_APPEND_ONLY" == '1' -o "$BORGW_APPEND_ONLY" == 'y' -o "$BORGW_APPEND_ONLY" == 'yes' ]; then
    borg_serve_cmd="$borg_serve_cmd --append-only"
  fi
  if [ -n "$BORGW_RESTRICT_PATH" ]; then
    borg_serve_cmd="$borg_serve_cmd --restrict-to-path $BORGW_RESTRICT_PATH"
  fi
  if [ -n "$BORGW_RESTRICT_REPOSITORY" ]; then
    borg_serve_cmd="$borg_serve_cmd --restrict-to-repository $BORGW_RESTRICT_REPOSITORY"
  fi
  if [ -n "$BORGW_STORAGE_QUOTA" ]; then
    borg_serve_cmd="$borg_serve_cmd --storage-quota $BORGW_STORAGE_QUOTA"
  fi

  if [ "$1" == '-s' -o "$1" == '--socket' ]; then
    print_args socat UNIX-LISTEN:"$2" "EXEC:$borg_serve_cmd"
    socat UNIX-LISTEN:"$2" "EXEC:$borg_serve_cmd" &
    print_args ssh -R "$2":"$3" "$SSH_ARGS" "$5" "BORG_RSH=\"$4 -s $3\"" "${@:6}"
    ssh -R "$2":"$3" "$SSH_ARGS" "$5" "BORG_RSH=\"$4 -s $3\"" "${@:6}"
  elif [ "$1" == '-t' -o "$1" == '--tcp' ]; then
    host=localhost
    print_args socat TCP-LISTEN:"$2" "EXEC:$borg_serve_cmd"
    socat TCP-LISTEN:"$2" "EXEC:$borg_serve_cmd" &
    print_args ssh -R "$2":"$host":"$3" "$SSH_ARGS" "$5" "BORG_RSH=\"$4 -t $3\"" "${@:6}"
    ssh -R "$2":"$host":"$3" "$SSH_ARGS" "$5" "BORG_RSH=\"$4 -t $3\"" "${@:6}"
  else
    echo "unknown method"
  fi
fi
