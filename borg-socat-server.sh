#!/usr/bin/env bash
if [ $# -lt 3 ]; then
  echo "usage: [-s|--socket] local-listening-uds.sock remote-connecting-uds.sock target-wrapper host <borg command>"
  echo "usage: [-t|--tcp] local-listening-port remote-connecting-port target-wrapper host <borg command>"
  echo "example: BORGW_RESTRICT_PATH=/path/to/repo $0 -s /tmp/local.sock /tmp/remote.sock /root/borg-socat-client.sh"\
    "backuped-server /root/borg create ssh://server/path/to/repo::{hostname}_{utcnow} path to backup"
# Serve parameters
#BORGW_RESTRICT_PATH
#BORGW_RESTRICT_REPOSITORY
#BORGW_APPEND_ONLY
#BORGW_STORAGE_QUOTA
# Other
#BORGW_DRYRUN : set to 1 to only print commands
#SSH_ARGS : arguments passed to ssh (as single quoted arg actually)
#ssh port can be placed with '"host -p 22"' instead of 'host', which will be passed as multiple args (unlike $SSH_ARGS)
else
  print_args() {
    # Test space quoting
    python -c "import sys; print(sys.argv[1:])" "$@"
  }

  borg_serve_cmd="./borg serve --umask 077"
  [ "$BORGW_APPEND_ONLY" == '1' -o "$BORGW_APPEND_ONLY" == 'y' -o "$BORGW_APPEND_ONLY" == 'yes' ] && borg_serve_cmd="$borg_serve_cmd --append-only"
  [ -n "$BORGW_RESTRICT_PATH" ] && borg_serve_cmd="$borg_serve_cmd --restrict-to-path $BORGW_RESTRICT_PATH"
  [ -n "$BORGW_RESTRICT_REPOSITORY" ] && borg_serve_cmd="$borg_serve_cmd --restrict-to-repository $BORGW_RESTRICT_REPOSITORY"
  [ -n "$BORGW_STORAGE_QUOTA" ] && borg_serve_cmd="$borg_serve_cmd --storage-quota $BORGW_STORAGE_QUOTA"

  if [ "$1" == '-s' -o "$1" == '--socket' ]; then
    print_args socat UNIX-LISTEN:"$2" "EXEC:$borg_serve_cmd"
    [ "$BORGW_DRYRUN" == "1" ] || socat UNIX-LISTEN:"$2" "EXEC:$borg_serve_cmd" &
    socat_pid=$!
    print_args ssh -R "$2":"$3" "$SSH_ARGS" $5 "BORG_RSH=\"$4 -s $3\"" "${@:6}"
    [ "$BORGW_DRYRUN" == "1" ] || ssh -R "$2":"$3" "$SSH_ARGS" $5 "BORG_RSH=\"$4 -s $3\"" "${@:6}"
    [ "$BORGW_DRYRUN" == "1" ] || kill $socat_pid
  elif [ "$1" == '-t' -o "$1" == '--tcp' ]; then
    host=localhost
    print_args socat TCP-LISTEN:"$2" "EXEC:$borg_serve_cmd"
    [ "$BORGW_DRYRUN" == "1" ] || socat TCP-LISTEN:"$2" "EXEC:$borg_serve_cmd" &
    socat_pid=$!
    print_args ssh -R "$2":"$host":"$3" "$SSH_ARGS" $5 "BORG_RSH=\"$4 -t $3\"" "${@:6}"
    [ "$BORGW_DRYRUN" == "1" ] || ssh -R "$2":"$host":"$3" "$SSH_ARGS" $5 "BORG_RSH=\"$4 -t $3\"" "${@:6}"
    [ "$BORGW_DRYRUN" == "1" ] || kill $socat_pid
  else
    echo "unknown method"
  fi
fi
