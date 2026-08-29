# brgen IRC bridge

A pure-Ruby IRC gateway that maps brgen's city channels onto the real IRC
protocol, so someone on Libera.Chat / EFnet / Undernet / Newnet can point a
client at brgen and land in the same `#brgen` room a phone browser sees.
Messages cross both ways; the modes (`@` op / `+` voice) and roster we already
built map straight onto IRC's `MODE` and `NAMES`.

## What's built (and tested)

- `lib/brgen/irc/message.rb` — parse/build one IRC protocol line.
- `lib/brgen/irc/session.rb` — a connection state machine: `NICK`/`USER`
  registration, `JOIN`, `PART`, `PRIVMSG`, `NAMES`, `PING`, `QUIT`, plus `#poll`
  for relaying web-side messages. No sockets — unit-tested against a fake
  bridge.
- `lib/brgen/irc/bridge.rb` — the seam to brgen's models: channel lookup
  (`Conversation.find_or_create_channel`), posting (`Message.create!` via a
  per-nick bridged user), history, roster (with `@`/`+`), and web→IRC deltas.
- `lib/brgen/irc/server.rb` — the socket harness (thread per client + a 2s poll
  thread, write mutex, per-thread AR connection).
- `bin/irc-gateway` — boots Rails and starts the server.
- `test/lib/brgen/irc_test.rb` — protocol + full session flows (10 examples).

brgen channels are anonymous by design, so a web viewer sees an IRC poster as an
anon handle; the nick is preserved on the IRC side. Only the known city channels
(`#brgen`, `#marketplace`, …) are joinable — a guessed `#slug` returns `403`.

## Going live (deliberate operator steps — not enabled by default)

The gateway binds `127.0.0.1:6667` and starts nothing on its own. To expose it:

1. **Install nothing extra** — it's pure Ruby, runs on the app's own bundle.
2. **Open a listener.** Either relayd-terminate TLS on 6697 and forward to
   `127.0.0.1:6667` (recommended — gives `ircs://`), or add a pf pass rule for
   6667 and set `IRC_HOST=0.0.0.0`. Plain 6667 is cleartext; prefer 6697.
3. **Enable the service.** Add `irc_gateway` to `pkg_scripts` in
   `/etc/rc.conf.local`, then `doas rcctl enable irc_gateway && doas rcctl start
   irc_gateway`. The rc.d script is `OPENBSD/etc/rc.d/irc_gateway`.
4. **DNS.** Point `irc.brgen.no` at the box so clients `/connect irc.brgen.no`.

## Known limits / next

- No `NICKSERV`/SASL auth — nicks are first-come per connection (fine for an
  anonymous bridge; add collision handling before a busy launch).
- Poll-based web→IRC relay (2s). A SolidCable/Redis subscription would cut
  latency and DB load at scale.
- DMs (`PRIVMSG` to a nick) aren't bridged yet — channels only.
- Per-nick bridged `User` rows accumulate; add a sweep like guest pruning.
