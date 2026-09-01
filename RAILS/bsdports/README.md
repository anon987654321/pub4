# bsdports

**Search the whole OpenBSD ports tree as fast as you can type.** bsdports is
full-text live search over ports with their dependencies, advisories and
maintainers, on Rails 8.1, SQLite with FTS5, Falcon, Hotwire and relayd.

Deploy it with `doas zsh RAILS/bsdports/bsdports.sh`, then prove it answers on
`127.0.0.1:47312/up` and `/health`. Both, not one: relayd keeps terminating TLS
after the app has gone, so a site that looks up from outside can be a closed port
underneath.

The ports data arrives by import. `bin/rails ports:import_now` with
`PLATFORM=openbsd` and `BSDPORTS_TREE_PATH=/usr/ports` reads a local tree
immediately; `bin/rails ports:import` queues the nightly-style run instead. What
the app is meant to do, as against what it does, is `apps.yml` under `bsdports`.
