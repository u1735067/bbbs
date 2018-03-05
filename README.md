Bash [Borg](https://www.borgbackup.org/) Backup Server
======================================================
[Borg](https://github.com/borgbackup/borg) wrappers for server [pull mode](https://github.com/borgbackup/borg/issues/900).
As distributions repositories may not always be updated, it is designed to work with the standalone version, installed in `/opt/borg`.

Requirement
-----------
 * bash
 * sudo
 * socat
 * git, to retrieve thoses scripts
 * curl, jq, gpg, to retrieve and verify borg binaries

Instructions
------------
You can `git clone https://github.com/Alex131089/bbbs` in `/opt/borg/` and run the installer.\
Obviously, you have to edit `do-backup.example` according to your needs.\
borg's dot path are symlinked to more accessible paths (`.cache/borg -> ~/cache`, `.config/borg -> ~/` (will expose `keys` and `security` directly), `.ssh -> ssh`).

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

Pre & post hooks on client
--------------------------

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
While [`Borg Backup Server`](http://www.borgbackupserver.com/) (BBS) has been [announced](https://github.com/borgbackup/borg/issues/2960#issuecomment-341742078), it is [not available yet](https://github.com/marcpope/bbs) and I needed a solution (preferably before my server crashes). Also, I don't want the clients to have to know how to reach the server.
This is ugly but probably the simplest for now (when using pull mode).
A correct solution could be to use `python` as wrapper, with `libssh` to setup the channel, and parsing nice configuration files.

Locale correction explanation
-----------------------------
The wrappers `borg` and `borg-client` will try to set a correct locale (meaning: with `UTF-8` charset).

### Why? 
Because Python relies on it to read filenames correctly. Most filesystems seems to only care about `bytes`, but the [convention is to use UTF-8](https://unix.stackexchange.com/questions/2089/what-charset-encoding-is-used-for-filenames-and-paths-on-linux) and most locales without the charset specifier (`.utf8`) doesn't not use UTF-8, so Python use that charset and fails to decode filenames properly.
Also, distributions like OMV can decide to set `LANG=C` before executing crons, which will make Python use the `ascii`/`ANSI` encoding.

However, except for `extract` / `fuse mouse` according to the issues, borg seems to handle that correctly ([even](https://github.com/borgbackup/borg/blob/5512db773a68ffa605598d8f9ef3b8afdb0c1b15/src/borg/archiver.py#L597) [though](https://github.com/python/cpython/blob/3.6/Lib/os.py#L4) [I'm](https://github.com/python/cpython/blob/3.6/Modules/posixmodule.c#L11856) [not](https://github.com/python/cpython/blob/3.6/Modules/posixmodule.c#L11707) [sure](https://github.com/python/cpython/blob/3.6/Include/unicodeobject.h#L1848) [why](https://github.com/python/cpython/blob/3.6/Objects/unicodeobject.c#L3877), as `args.path` are `str`, so [scandir](https://docs.python.org/3/library/os.html#os.scandir) will return `str` which mean they are decoded?).

More informations (about this mess): 
 * https://stackoverflow.com/questions/27366479/python-3-os-walk-file-paths-unicodeencodeerror-utf-8-codec-cant-encode-s
 * https://unix.stackexchange.com/questions/2089/what-charset-encoding-is-used-for-filenames-and-paths-on-linux
 * https://bugs.python.org/issue13717
 * https://bugs.python.org/issue19846
 * https://bugs.python.org/issue19847
 * https://bugzilla.redhat.com/show_bug.cgi?id=902094
 * https://gist.github.com/Alex131089/8b4a7e346c040b09c5b8ac99951fda29

### How?
To do so, it'll parse locales by priority (`LC_ALL` > `LC_CTYPE` > `LANG`), testing if it's indicating `UTF-8` charset, or if it's not trying to find the `UTF-8` alternative of this locale, or ultimately unsetting it (to let the chance to lower priority locales).\
If there's no locale left, it'll then try to see if there's any `UTF-8` locale available, setting `LC_CTYPE`, starting by `C`, English (`en_GB`, `en_US`, `en_*`) and ultimatly the first found.\
In the end, if there's really no UTF-8 locale available, none of `LC_ALL`, `LC_CTYPE`, `LANG` should be set, thus triggering the [python 3 default UTF-8](https://docs.python.org/3/howto/unicode.html#unicode-filenames), but I wasn't able to reproduce this behavior:

```
# export -n LC_ALL LC_CTYPE LANG; python3 -c 'import sys; print(sys.version); print(sys.getfilesystemencoding())'
3.4.2 (default, Oct  8 2014, 10:45:20)
[GCC 4.9.1]
ascii
```
