# MASTER lib/ corruption repair — 2026-06-13

## What was wrong
The working tree **and HEAD** (`006a7083` + a few prior commits) carried automated-fix
corruption that made MASTER non-parsing — it could not boot. Two classes:

1. **Freeze-autofix corruption** — `.freeze` written onto the *opening* bracket of
   constants (`FOO = {.freeze ... }.freeze`). Never-valid Ruby. 102 occurrences, 58 files.
2. **Deleted/garbled lines** — missing `end`, missing `case` headers, trailing commas
   inside lambda/blocks, truncated `return Result.err(...,` guards, `case`-less `when`,
   `module` left in a method body, dynamic constant assignment. ~58 files.

Origin is consistent with the last two commits enabling a background FixLoop + auto-approve
("Force-allow all tool calls…", "start FixLoop background and approve tools by default"):
MASTER damaged its own committed source.

## What I changed (116 files in MASTER/lib, all uncommitted — review before committing)
- **58 files** — removed the misplaced `{.freeze`/`[.freeze` (closings already had `.freeze`).
- **~56 files** — recovered byte-for-byte from each file's most-recent **clean ancestor commit**
  (almost all exactly 1 commit behind HEAD, i.e. only the corrupting commit's delta was reverted).
- **2 files hand-fixed** (no clean ancestor existed): `lib/builder.rb` (trailing commas in
  TOOL_MAP lambdas + restored `build_tools` `filter_map` body) and `lib/reach/web_search.rb`
  (trailing commas in nested blocks + reconstructed the `HTTP_OK` guard).

A backup of the broken tree is in the session outputs (`lib_broken_backup/`).

## Verification done locally (Ruby 3.0.2 sandbox)
This box runs Ruby 3.0.2; MASTER targets ruby34, so `ruby -c` alone rejects valid ruby34
syntax (shorthand hash `foo(x:, y:)`, anonymous block `def m(&)`). I wrote a validator that
neutralizes those constructs then parses. Result: **all 255 lib files + bin/cli + tools/ pass
structural validation; 0 freeze corruption.** This is strong but not authoritative.

## You must verify on ruby34 (I could not reach brgen.no from the sandbox — DNS not allow-listed)
These repairs are in your **local** workspace only; the server checkout is still the corrupted HEAD.

```zsh
# 1. review the repair
cd ~/pub4 && git diff --stat HEAD            # 116 files; spot-check a few recoveries
# 2. authoritative parse check (run where ruby34 lives)
cd MASTER
for f in $(find lib bin tools -name '*.rb'); do ruby34 -c "$f" >/dev/null || echo "FAIL $f"; done
# 3. boot + self-scan (safe mode is default)
bundle34 exec ruby bin/cli
# 4. if good, commit + deploy
cd ~/pub4 && git add -A MASTER/lib MASTER/REPAIR_NOTES.md && git commit -m "repair: undo autofix corruption in MASTER/lib (un-parseable tree)"
# then on the server: git pull && doas rcctl restart master
```

## Not done (and why)
- **"Finish + delete TODO.md"** — `MASTER/TODO.md` has 1,773 open items (mostly aspirational
  research/rename backlog) and `DEPLOY/TODO.md` similar. Not session-scoped, and moot while the
  tree did not parse. Recommend deleting neither until MASTER boots clean and the backlog is triaged.
- **Run MASTER over itself** — requires a booting tree on ruby34 with API keys; do step 3 above.
