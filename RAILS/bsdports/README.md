# bsdports

**Search the whole OpenBSD ports tree as fast as you can type.** bsdports gives every port a
page of its own, with its dependencies, its security advisories and its maintainer, and finds
any of them in the time it takes to press a key.

It is a Rails 8.2.0.alpha app on Ruby 4.0.5, with SQLite, Falcon and Hotwire. Search runs
through an FTS5 index over port names and comments, kept beside the data in the same database.
The pages wear the terminal-green look of OpenBSD itself, flat and dense, with one line to a
port, because the index is the product. The app follows the shared engine's layout and
accessibility contracts and takes its design values from MASTER, so it differs from brgen and
amber in dialect and not in grammar. Its interface is Norwegian by default, like the other two
apps. The promise, the stack and the status of every feature are in `apps.yml`, under
`bsdports`.

The ports data arrives by import. The rake task `ports:import_now` reads a local tree at once.
Set `PLATFORM` to `openbsd` and `BSDPORTS_TREE_PATH` to `/usr/ports`, and it reports how many
ports it loaded. The task `ports:import` queues the same work on Solid Queue instead, and
`FTP_FALLBACK`, on by default, lets the importer fall back to FTP when the local tree yields no
ports.

The shared engine's social routes (notifications, reactions, reports) are off here, because the
schema has none of their tables. Setting `BSDPORTS_SOCIAL=1` draws them, and it should wait
until the migrations land. Conditional GET is on for a port page and a maintainer page, keyed on
the viewer, because those pages carry a watch button and a comment form. The shared README
gives the reasons.

A deploy runs through `OPENBSD/bin/vps-deploy bsdports`, which runs `bsdports.sh` on vm23 and
copies the tree to `/home/bsdports/app`. The shared engine sits beside it at
`/home/bsdports/__shared`. Every deploy sheds amber and bsdports together, and relayd keeps
answering TLS while their ports are closed, so a site that looks alive from outside can be
down underneath. After any deploy, prove that `127.0.0.1:47312` answers `/up` and `/health`.
Both matter, because `/up` says the process lives and `/health` says Solid Cache, Solid Queue
and the database are in order.

## Try it

```zsh
cd RAILS/bsdports
PLATFORM=openbsd BSDPORTS_TREE_PATH=/usr/ports bin/rails ports:import_now
bin/ci
```
