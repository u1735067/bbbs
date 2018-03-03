Bash [Borg](https://www.borgbackup.org/) Backup Server
======================================================
[Borg](https://github.com/borgbackup/borg) wrappers for server [pull mode](https://github.com/borgbackup/borg/issues/900).
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
client> git clone git@github.com:Alex131089/bbbs.git /opt/borg
client> borg/installer.sh install-client

server> yum install git sudo socat curl jq
server> git clone git@github.com:Alex131089/bbbs.git /opt/borg
server> borg/installer.sh install-server

server> /opt/borg/ssh-gen-copy-key -g -k server-name_hypervisor -c -u borg -- root@server-name -p 22
server> gw_key=~borg/ssh/key_server-name_hypervisor; /opt/borg/ssh-gen-copy-key -g -k server-name_vm-1 -c -u borg -- root@172.16.0.1 -p 22 -o ProxyCommand="ssh -i$gw_key -W %h:%p server-name.fqdn -p 22"

server> /opt/borg/borg init -e authenticated-blake2 /srv/borg/server-name/hypervisor
server> /opt/borg/borg init -e authenticated-blake2 /srv/borg/server-name/vm-1

server> sudo -u borg /opt/borg/do-backup
```

`borg-client` will call `~borg/backup-pre` and `~borg/backup-pre` on the client before and after running `borg create`, you can use them to dump a sql database and remove it for example.

To manage ssh connexion parameters, you can also use `ssh_config` instead, for example:
```
server> cat ~borg/ssh/config
Host *
        User borg

Host server-name
        Port 22
        IdentityFile ~borg/ssh/key_server-name_hypervisor

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

**/!\ Don't forget to set executable bit (`chmod +x ~borg/backup-p*`) on them!**

### Mysql
Cache credentials in `~borg/.mylogin.cnf` (see [`mysqldump`](https://dev.mysql.com/doc/refman/en/mysqldump.html), [`mysql_config_editor`](https://dev.mysql.com/doc/refman/en/password-security-user.html)):

```
su borg -c "mysql_config_editor set --user=root --password"
```
or for `MariaDB` in `~borg/.my.cnf` (see [`mysqldump`](https://mariadb.com/kb/en/library/mysqldump/)):
```
[mysqldump]
user=mysqluser
password=secret
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

### Splunk
See [Backup indexed data](http://docs.splunk.com/Documentation/Splunk/latest/Indexer/Backupindexeddata), [Index backup strategy](https://www.splunk.com/blog/2011/12/20/index-backup-strategy.html).

`~borg/backup-pre`:
```bash
#!/usr/bin/env bash

echo "- Stopping Splunk ..."
service splunk stop
#systemctl stop splunk
echo "- Stopping Splunk ... Done"
```

`~borg/backup-post`:
```bash
#!/usr/bin/env bash

echo "- Starting Splunk ..."
service splunk start
#systemctl start splunk
echo "- Starting Splunk ... Done"
```

Why ?
-----
While [`Borg Backup Server`](http://www.borgbackupserver.com/) (BBS) has been [announced](https://github.com/borgbackup/borg/issues/2960#issuecomment-341742078), it is [not available yet](https://github.com/marcpope/bbs) and I needed a solution (preferably before my server crashes).
This is ugly but probably the simplest for now (when using pull mode).
A correct solution could be to use `python` as wrapper, with `libssh` to setup the channel, and parsing nice configuration files.
