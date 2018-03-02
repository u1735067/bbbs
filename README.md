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
You have to edit `start-backup.sh` according to your needs.

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