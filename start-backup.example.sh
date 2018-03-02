#!/usr/bin/env bash

# https://borgbackup.readthedocs.io/en/stable/usage/create.html
# https://borgbackup.readthedocs.io/en/stable/usage/help.html#borg-help-patterns
# https://borgbackup.readthedocs.io/en/stable/usage/help.html#borg-help-placeholders
# https://refspecs.linuxfoundation.org/FHS_3.0/fhs-3.0.html
# http://www.pathname.com/fhs/pub/fhs-2.3.html
# https://manpages.debian.org/stretch/manpages-fr-extra/date.1.fr.html

# https://borgbackup.readthedocs.io/en/stable/faq.html#i-am-seeing-a-added-status-for-an-unchanged-file
# https://borgbackup.readthedocs.io/en/stable/faq.html#it-always-chunks-all-my-files-even-unchanged-ones

# Differentiated targets / dataset:
# sys = / /boot /etc /opt /srv /var -/var/log
# homes = /root /home
# logs = /var/log

COMMON_TARGET="
  /
  /boot
  /etc
  /root
  /home
  /opt
  /srv
  /var
  /var/log
"
COMMON_EXCLUDE="
  --exclude /lost+found
  --exclude /var/cache/
  --exclude /home/*/.cache
"
# For when not using --one-file-system
NONONE_EXCLUDE="
  --exclude /sys
  --exclude /proc
  --exclude /dev
  --exclude /run
  --exclude /mnt
"
# --exclude /var/run # -> /run

## Global
export BORGW_APPEND_ONLY=1

## Per client
# Hypervisor - https://pve.proxmox.com/wiki/Linux_Container
export BORGW_RESTRICT_REPOSITORY=/srv/borg/server-name/hypervisor
export SSH_ARGS=

host=server-name.fqdn
port=22
log_file="logs/"$(date --utc "+%Y-%m-%d_%H.%M.%SZ")"_$host.log"

/opt/borg/wrapper-server.sh -t 12345 12345 /opt/borg/wrapper-client.sh "$host -p $port -oBatchMode=yes"
  sudo /opt/borg/borg.bin create \
    --show-version --show-rc --verbose --list --stats --one-file-system --keep-exclude-tags \
    ssh://backup-server/./::{utcnow:%Y-%m-%d} \
    #--comment 'Test xfs' \
    "$COMMON_EXCLUDE" \
    #--exclude /var/lib/lxc \ # config, "rootfs", "devices" (empty)
    --exclude /var/lib/lxcfs/ \ # ~ /proc for lxc
    --exclude /var/lib/vz/images/ \ # images, templates
    "$COMMON_TARGET" /etc/pve \
      | tee $log_file

# VM 1
export BORGW_RESTRICT_REPOSITORY=/srv/borg/server-name/vm1
export SSH_ARGS="-o ProxyCommand=ssh -W %h:%p server-name.fqdn -p 22"

host=172.16.0.1
port=22
log_file="logs/"$(date --utc "+%Y-%m-%d_%H.%M.%SZ")"_$host.log"

/opt/borg/wrapper-server.sh -t 12345 12345 /opt/borg/wrapper-client.sh "$host -p $port -oBatchMode=yes"
  sudo /opt/borg/borg.bin create \
    --show-version --show-rc --verbose --list --stats --one-file-system --keep-exclude-tags \
    ssh://backup-server/./::{utcnow:%Y-%m-%d} \
    "$COMMON_EXCLUDE" \
    "$COMMON_TARGET"
      | tee $log_file
