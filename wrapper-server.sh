#!/usr/bin/env bash
#BORGW_PATH=/srv/borg
#BORGW_PATH=/opt/borg
BORGW_PATH=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

borg_user=borg
if [ "$(id --user --name)" != "$borg_user" -o $# -lt 3 ]; then
  echo "$0 must be run as $borg_user
  echo "usage: sudo -u $borg_user [env vars] $0 [-s|--socket] local-listening-uds.sock remote-connecting-uds.sock target-wrapper host <borg command>"
  echo "usage: sudo -u $borg_user [env vars] $0 [-t|--tcp] local-listening-port remote-connecting-port target-wrapper host <borg command>"

  echo "example: sudo -u $borg_user BORGW_RESTRICT_PATH=/path/to/repos $0 -s /tmp/local.sock /tmp/remote.sock /opt/borg/wrapper-client.sh"\
    "\"backuped-server -p 22\" /root/borg create ssh://backup-server/./my-repo::{hostname}_{utcnow} paths to backup"
  echo "example: sudo -u $borg_user SSH_ARGS=\"-o ProxyCommand=ssh -W %h:%p gateway-server -p 22\" BORGW_RESTRICT_REPOSITORY=/path/to/repos/repo"\
    "$0 -s /tmp/local.sock /tmp/remote.sock /opt/borg/wrapper-client.sh backuped-server /root/borg"\
    "create ssh://backup-server/./::{hostname}_{utcnow} paths to backup"

# Serve parameters
#BORGW_RESTRICT_PATH
#BORGW_RESTRICT_REPOSITORY
#BORGW_APPEND_ONLY
#BORGW_STORAGE_QUOTA
# Other
#BORGW_DRYRUN: set to 1 to only print commands
#SSH_ARGS: arguments passed to ssh (as single quoted arg actually)
#ssh port can be placed with '"host -p 22"' instead of 'host', which will be passed as multiple args (unlike $SSH_ARGS)
else
  print_args() {
    # Test space quoting
    python -c "import sys; print(sys.argv[1:])" "$@"
  }
  print_exec() {
    print_args "$@"
    [ "$BORGW_DRYRUN" == "1" ] || "$@"
  }

  borg_serve_cmd=$BORGW_PATH"/borg.bin serve --umask 077"
  [ "$BORGW_APPEND_ONLY" == '1' -o "$BORGW_APPEND_ONLY" == 'y' -o "$BORGW_APPEND_ONLY" == 'yes' ] && borg_serve_cmd="$borg_serve_cmd --append-only"
  [ -n "$BORGW_STORAGE_QUOTA" ] && borg_serve_cmd="$borg_serve_cmd --storage-quota $BORGW_STORAGE_QUOTA"
  if [ -n "$BORGW_RESTRICT_REPOSITORY" ]; then
    borg_serve_cmd="$borg_serve_cmd --restrict-to-repository $BORGW_RESTRICT_REPOSITORY"
    cd $BORGW_RESTRICT_REPOSITORY
  elif [ -n "$BORGW_RESTRICT_PATH" ]; then
    borg_serve_cmd="$borg_serve_cmd --restrict-to-path $BORGW_RESTRICT_PATH"
    cd $BORGW_RESTRICT_PATH
  fi

  [ -z "$SSH_ARGS" ] && SSH_ARGS=-- # To avoid passing an empty argument
  if [ "$1" == '-s' -o "$1" == '--socket' ]; then
    print_args socat UNIX-LISTEN:"$2" "EXEC:$borg_serve_cmd"
    [ "$BORGW_DRYRUN" == "1" ] || socat UNIX-LISTEN:"$2" "EXEC:$borg_serve_cmd" &
    socat_pid=$!
    print_exec ssh -R "$2":"$3" $5 "$SSH_ARGS" "BORG_RSH=\"$4 -s $3\"" "${@:6}"
    [ "$BORGW_DRYRUN" == "1" ] || (kill -0 "$socat_pid" && kill $socat_pid)
  elif [ "$1" == '-t' -o "$1" == '--tcp' ]; then
    host=localhost
    print_args socat TCP-LISTEN:"$2" "EXEC:$borg_serve_cmd"
    [ "$BORGW_DRYRUN" == "1" ] || socat TCP-LISTEN:"$2" "EXEC:$borg_serve_cmd" &
    socat_pid=$!
    print_exec ssh -R "$2":"$host":"$3" $5 "$SSH_ARGS" "BORG_RSH=\"$4 -t $3\"" "${@:6}"
    [ "$BORGW_DRYRUN" == "1" ] || (kill -0 "$socat_pid" && kill $socat_pid)
  else
    echo "unknown method"
  fi
fi
