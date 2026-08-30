# trymbot

**Trymbot is a small, eager, slightly clumsy robot that lives in a Telegram chat
and teaches one eleven-year-old to write Ruby and build a beat — running on the
machine in the room with him, so nothing he says has to leave the house.**

Trymbot had a first life as a second face on the MASTER web tier, selected by
host: trymbot.brgen.no served the same process as ai.brgen.no, and everything
that differed with it lived in one deletable file. That cost a certificate, a
relayd line and a fifth process on a box with one gigabyte of memory, all to
serve one person. Telegram costs none of those. The bot long-polls, so it opens
no port, needs no inbound route, and does not care that a laptop moves between
networks. What survives from the first life is the part worth keeping: the
brief, in Norwegian, that makes Trymbot who he is.

He stammers when he gets excited, and he gets excited often. He says pip and
brrzt while he thinks. He is a little unsure of himself, always kind, and he
laughs at his own mistakes rather than apologising for them. He knows two
things well and loves teaching both: Ruby, in programs short enough to type out
by hand, and how a beat is put together. He asks what you want to make and then
builds it with you one small step at a time, rather than handing over the whole
answer. Now and then, not every time, he mentions that your mum loves you.

A reply can come from several places, and they are tried in order. Ollama on
this machine goes first, because it is the only one where a child's chat log
stays on the hardware it was typed into. Behind it stand the coding agents
already installed here — gemini, claude, grok and codex — which are slower and
cost money but write excellent Norwegian. They run in a scratch directory, so a
tool call has nothing of ours within reach. A model that fails to load is not
tried again for the rest of the run, because failing is not free: gemma4 at
twenty-six billion parameters takes about two minutes on this host to report
that it cannot start, and without that memory every message Trym typed would
wait behind it.

Two things live outside the repository, in a directory under your home. One is
the token from BotFather, which is complete control of the bot and belongs
nowhere near a public remote. The other is the allowlist, which decides who
Trymbot will speak to. A bot username is public, so anyone who finds it can open
a chat, and an empty allowlist therefore means nobody rather than everybody.
Start the bot, have Trym send it one message, and the chat id it refuses in the
log is the one to write down.

To read the persona, open trymbot.rb: the brief is near the top, in plain
Norwegian, and it is the only part of the file that is not transport. Tune it
with the ask command, which runs one turn through the same chain and prints the
answer, so the voice can be adjusted before a token exists at all.

## Running it

```zsh
ruby trymbot.rb check          # what is configured, and what can answer
ruby trymbot.rb ask "hei!"     # one turn, no Telegram, for tuning the brief
ruby trymbot.rb run            # long-poll Telegram until interrupted
```

The suite is `rake test:trymbot` from STUDIO, and `ruby STUDIO/gate.rb` probes
that the entry point still boots.
