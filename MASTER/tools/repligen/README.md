# repligen

repligen is MASTER’s stable entrypoint for Replicate.com generation workflows. The implementation still lives in DEPLOY/tools/repligen.rb; MASTER/tools/repligen.rb is the tool surface used by command dispatch and tool contracts, forwarding arguments unchanged to the legacy code.

Run ruby MASTER/tools/repligen.rb --help for usage. Typical invocations include sync with a limit such as 100, search with a query such as upscale, and stats for database summaries. Dependencies are Ruby, the sqlite3 gem, REPLICATE_API_TOKEN or credentials in ~/.config/repligen/config.json, and network access to Replicate. The legacy implementation may install missing gems and maintains a local SQLite database.

MASTER exposes repligen as the slash command /repligen with tool contract repligen, permission network, and side effects on network, filesystem, and process. Do not add new DEPLOY-facing call sites; new callers should use this MASTER entrypoint or /repligen.