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
client> apt-get install curl jq sudo socat
client> cd /opt/
client> git clone git@github.com:Alex131089/bbbs.git borg
client> cd borg/
client> ./installer.sh install-client
client> visudo

server> apt-get install curl jq sudo socat
server> cd /opt/
server> git clone git@github.com:Alex131089/bbbs.git borg
server> cd borg/
server> ./installer.sh install-server
server> visudo

server> ./ssh-gen-copy-key -g -k server-name_hypervisor -c -u borg -- root@server-name -p 22
server> gw_key=~borg/ssh/server-name_hypervisor.key; ./ssh-gen-copy-key -g -k server-name_vm-1 -c -u borg -- root@172.16.0.1 -p 22 -o ProxyCommand="ssh -i$gw_key -W %h:%p server-name.fqdn -p 22"

server> ssh-keygen -F '[server-name]:22' | sed '/^#/d' >> ~borg/ssh/known_hosts
server> ssh-keygen -F '172.16.0.1' | sed '/^#/d' >> ~borg/ssh/known_hosts

server> /opt/borg/borg init -e authenticated-blake2 /srv/borg/server-name/hypervisor
server> /opt/borg/borg init -e authenticated-blake2 /srv/borg/server-name/vm-1

server> sudo -u borg ./do-backup
```

`borg-client` will call `~borg/backup-pre` and `~borg/backup-pre` on the client before and after running `borg create`, you can use them to dump a sql database and remove it for example.


Diagram
-------
```
╔══════╦════════════════════════════════════════════╦════════════════════════════════════════╗
║      ║                   Server                   ║                 Client                 ║
╠══════╬════════════════════════════════════════════╬════════════════════════════════════════╣
║ root ║  sudo                                      ║            borg ──► wrapper ──► socat  ║
║      ║    │                                       ║              ▲                    |    ║
╠══════╬════┼═══════════════════════════════════════╬══════════════┼════════════════════╪════╣
║ borg ║    └─► wrapper                             ║              │                    │    ║
║      ║           ├──────────────────────► ssh ====╬===► ssh ──► sudo                  │    ║
║      ║           └─► socat ──► borg serve  ┊      ║      ┊                            │    ║
║      ║                  ▲                  ┊      ║      ┊                            │    ║
║      ║                  └──────────────────╘======╬======╛◄───────────────────────────┘    ║
╚══════╩════════════════════════════════════════════╩════════════════════════════════════════╝
  ===== = ssh channel
```