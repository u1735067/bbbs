Bash Borg Backup Server
=======================
Borg wrappers for server [pull mode](https://github.com/borgbackup/borg/issues/900).
As distributions repositories may not always be updated, it is designed to work with the standalone version, installed in `/opt/borg`.

Requirement
-----------
 * Bash
 * sudo
 * socat
 * git, to retrieve thoses scripts
 * curl, jq, gpg, to retrieve and verify borg binaries

Instructions
------------
You can `git clone https://github.com/Alex131089/bbbs` in `/opt/borg/` and run the installer.
Obviously, ou have to edit `do-backup.example` according to your needs.

```
client> apt-get update && apt-get install git sudo socat curl jq
client> cd /opt/
client> git clone git@github.com:Alex131089/bbbs.git borg
client> cd borg/
client> ./installer.sh install-client
client> visudo

server> apt-get update && apt-get install git sudo socat curl jq
server> cd /opt/
server> git clone git@github.com:Alex131089/bbbs.git borg
server> cd borg/
server> ./installer.sh install-server
server> visudo

server> ./ssh-gen-copy-key -g -k server-name_hypervisor -c -u borg -- root@server-name -p 22
server> gw_key=~borg/ssh/server-name_hypervisor.key; ./ssh-gen-copy-key -g -k server-name_vm-1 -c -u borg -- root@172.16.0.1 -p 22 -o ProxyCommand="ssh -i$gw_key -W %h:%p server-name.fqdn -p 22"

server> /opt/borg/borg init -e authenticated-blake2 /srv/borg/server-name/hypervisor
server> /opt/borg/borg init -e authenticated-blake2 /srv/borg/server-name/vm-1

server> sudo -u borg ./do-backup
```

`borg-client` will call `~borg/backup-pre` and `~borg/backup-pre` on the client before and after running `borg create`, you can use them to dump a sql database and remove it for example.

To manage ssh connexion parameters, you can also use `ssh_config` instead, for example:
```
server> cat ~borg/ssh/config
Host *
        User borg

Host server-name
        Port 22
        IdentityFile ~borg/ssh/server-name_hypervisor.key

Host 172.16.*.*
        ProxyCommand ssh -F ~borg/ssh/config -W %h:%p server-name
```


Diagram
-------
```
╔══════╦════════════════════════════════════════════════════╦══════════════════════════════════════════════════════════════╗
║      ║                       Server                       ║                            Client                            ║
╠══════╬════════════════════════════════════════════════════╬══════════════════════════════════════════════════════════════╣
║ root ║  sudo                                              ║            borg-client ─┬─► ~borg/backup-pre                 ║
║      ║    │                                               ║              ▲          ├─► borg create ─► wrapper ─► socat  ║
║      ║    │                                               ║              │          └─► ~borg/backup-post           │    ║
║      ║    │                                               ║              │                                          │    ║
╠══════╬════┼═══════════════════════════════════════════════╬══════════════┼══════════════════════════════════════════╪════╣
║ borg ║    └─► do-backup                                   ║              │                                          │    ║
║      ║             └─► wrapper                            ║              │                                          │    ║
║      ║                   ├──────────────────────► ssh ====╬===► ssh ──► sudo                                        │    ║
║      ║                   └─► socat ──► borg serve  ┊      ║      ┊                                                  │    ║
║      ║                          ▲                  ┊      ║      ┊                                                  │    ║
║      ║                          └──────────────────╘======╬======╛◄─────────────────────────────────────────────────┘    ║
╚══════╩════════════════════════════════════════════════════╩══════════════════════════════════════════════════════════════╝
  ===== = ssh channel
```

Pre & post hooks
----------------

### Mysql
Cache credentials in `.mylogin.cnf` (see [mysqldump](https://dev.mysql.com/doc/refman/en/mysqldump.html), [mysql_config_editor](https://dev.mysql.com/doc/refman/en/password-security-user.html)):
```
su borg -c "mysql_config_editor set --user=root --password"
```

`~borg/backup-pre`:
```bash
#!/usr/bin/env bash

echo "- Dumping MySQL ..."
mkdir --parents /var/backups/mysql
mysqldump --all-databases --single-transaction | gzip --fast --rsyncable > /var/backups/mysql/borg-dump_$(date --utc "+%Y-%m-%d_%H.%M.%SZ").sql.gz
echo "- Dumping MySQL ... Done"
```

`~borg/backup-post`:
```bash
#!/usr/bin/env bash

echo "- Removing MySQL Dump ..."
rm -f /var/backups/mysql/borg-*
echo "- Removing MySQL Dump ... Done"
```