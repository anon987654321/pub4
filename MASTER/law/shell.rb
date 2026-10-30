# frozen_string_literal: true

# law/shell.rb — every shell law, one Law.define per law.
Law.define(:DOLLAR_PAREN) do
  source "ShellCheck SC2006 — $() over backticks"
  # A backtick followed by a method call is Ruby, not shell. drain-jobs.sh and
  # prune-guests.sh both embed `ruby34 -e '...'` to read the load average, and
  # inside that the backticks are Ruby's own command substitution — where they
  # are correct and `$()` is not a thing. Shell never writes `` `cmd`.method ``,
  # so the chain is the tell, and it costs nothing a real finding would have.
  detect { |line| line.match?(/`[^`]+`/) && !line.match?(/`[^`]+`\s*\.\s*\w/) }
  fix "Use $(command) — nestable and readable."
  bad  "now=`date`"
  good "now=$(date)"
end

# DOUBLE_BRACKET lives once, in the registry (js_laws.rb): it reads the
# shebang first — [[ ]] is a keyword in zsh/bash but not POSIX sh, so
# telling a /bin/sh script to use it is telling it to break. A line
# detector cannot see the shebang; the shebang-aware twin wins, the same
# judgment that kept QUOTE_VARIABLES in the registry.

# New. Restores the guard added after the 2026-01-05 incident (16 untracked
# files batch-deleted before a conversion step) that did not survive the
# master.yml -> MASTER migration. Consequence class: unrecoverable data loss.
Law.define(:NEVER_BATCH_DELETE) do
  source "master.yml v66 file_deletion_protocol — never batch-delete files"
  # File deletion lives here, and only here. GUARD_EXPENSIVE_OPS carried a bare
  # `rm -rf` too, so one question had two instruments free to disagree; it keeps
  # the database sweeps, this keeps the filesystem. The root and home targets
  # came across with it — an unbounded `rm -rf /` is the same consequence class
  # as a glob and the same rule should say so.
  #
  # `${app_dir}` is a variable expansion, not a brace glob, and the `{` in it
  # was four of this law's six findings — every scoped removal in the deploy
  # pipeline. Blanked before the glob test, since a `{` that survives is one
  # somebody typed.
  # An array literal is the fourth branch's exemption, and it is what the other
  # three already test for. A glob, a bare `$var` and a `Dir[]` are all
  # dangerous because the set is unknown until the line runs; the `.each { rm }`
  # branch asked only whether there was a loop, so it read a receiver spelled out
  # in full as the same hazard. `%w[.mp3 .job .err .meta.json].each { |ext|
  # rm_f(dir + ext) }` — the tts test's teardown — names how many files go and
  # which, and each call removes one named path, which is what the fix line asks.
  # `Dir[...]` keeps firing: the `[` there follows a word character, so the
  # bracket belongs to an index rather than to a literal.
  detect do |line|
    bare = line.gsub(/\$\{[^}]*\}/) { |m| "\0" * m.length }
    enumerated = /(?:%[wi][\[({][^\])}]*[\])}]|(?<![\w\])])\[[^\[\]]*\])\s*\.each\s*\{/
    bare.match?(/\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)*[^\s;|&]*[*?{]/) ||
      bare.match?(%r{\brm\s+-[a-zA-Z]*[rf][a-zA-Z]*\s+(?:"?/"?\s*(?:$|;)|"?~|\$\w+)}) ||
      line.match?(/FileUtils\.rm(_r|_rf|_f)?\(?\s*Dir\[/) ||
      (line.match?(/\.each\s*\{[^}]*(?:File\.delete|FileUtils\.rm)/) && !line.match?(enumerated))
  end
  fix "Delete one named path per call and confirm first; globs and .each { rm } need an explicit operator ack."
  bad  <<~RUBY
    FileUtils.rm_rf(Dir["tmp/*.txt"])
    system("rm -f build/*.o")
    stale.each { |f| File.delete(f) }
  RUBY
  good <<~RUBY
    FileUtils.rm("tmp/session.txt")
    system("rm", "-f", "build/main.o")
    File.delete(path) if confirmed?(path)
    %w[.mp3 .job].each { |ext| FileUtils.rm_f(base + ext) }
  RUBY
end

Law.define(:NO_INLINE_ASSETS_IN_SHELL) do
  source "RAILS/__shared frontend convention"
  detect { |line| line.match?(/<style\b|<script\b/) }
  fix "Move the markup into app/views and the style into a tracked stylesheet."
  bad  "print '<style>body{}</style>' > index.html"
  good "cp app/assets/site.css out/"
end

# QUOTE_VARIABLES lives once, in the registry (js_laws.rb): quoting is a
# fact about the interpreter — zsh does not word-split or glob unquoted
# parameter expansions; sh, ksh and bash all do — and only the registry can
# read the shebang. 455 of the deep scan's 573 quoting errors were idiomatic
# zsh flagged by a sh doctrine.

# New (2026-09-17, operator ask). Bash is banned: the deploy target is
# OpenBSD, where bash is not in base and /bin/sh is ksh; the operator's
# dialect is zsh; and a lane's default shell idiom is bash, whose word
# splitting and globbing the QUOTE_VARIABLES comment already had to carve
# around. `sh` shebangs stay legal — vm23's own rc.d and maintenance scripts
# are POSIX sh and must run where bash does not exist — so this law bites the
# one interpreter that is neither portable nor the house dialect.
Law.define(:ZSH_SHEBANG) do
  source "House rule: zsh, not bash — no bash in OpenBSD base, zsh is the operator dialect"
  scope :file
  detect { |text| text.match?(%r{\A#![^\n]*\bbash\b}) }
  fix "Use #!/usr/bin/env zsh, or #!/bin/sh when vm23 must run it."
  bad <<~X
    #!/bin/bash
    set -euo pipefail
  X
  good <<~X
    #!/usr/bin/env zsh
    set -euo pipefail
  X
end

# New (2026-10-30, operator ask). data/laws.yml `zsh.banned_commands` was a list
# with readers but no Law: MASTER's own shell warned and ran the command, the
# coding-harness hook kept a second copy of the list, and no scan read the repo's
# scripts at all. This is the scan, through the same Io::GnuTextTools lexer the
# hook and Io::Shell judge with, so the three cannot disagree about what a line runs.
#
# zsh scripts only. A #!/bin/sh or ksh script is what ZSH_SHEBANG keeps legal for
# vm23's rc.d and maintenance work, which must run on OpenBSD base, where neither
# zsh nor the replacements this law names are guaranteed.
Law.define(:ZSH_NATIVE_PATTERNS) do
  source "data/laws.yml zsh.banned_commands — Ruby and zsh, not GNU text tools"
  check do |text, file|
    zsh = text.match?(%r{\A#![^\n]*\bzsh\b}) || (file.end_with?(".zsh") && !text.start_with?("#!"))
    next [] unless zsh

    tools = Master::Io::GnuTextTools.new(Master.law("zsh"))
    lines = Master::Io::ShellLexer.blank_heredoc_bodies(text).lines
    lines.each_with_index.flat_map do |line, index|
      tools.banned_in(line).map do |name|
        finding(line: index + 1, message: "ZSH_NATIVE_PATTERNS: #{name} — use #{tools.replacement(name)}")
      end
    end
  end
  fix "Write the zsh expansion, glob or Ruby expression data/laws.yml names for the banned command."
  bad <<~X
    #!/usr/bin/env zsh
    count=$(wc -l < log)
  X
  good <<~X
    #!/usr/bin/env zsh
    lines=( ${(f)"$(<log)"} )
    print ${#lines}
  X
end

Law.define(:STRICT_MODE_ZSH) do
  source "Shell strict mode set -euo pipefail (Google Shell Style Guide)"
  scope :file
  # A law that fires on what is MISSING cannot be silenced by blanking a line,
  # which is all `scan: intentional` does — considered_text removes the marker
  # and the absent `set -e` is still absent. `absent` is checked against the raw
  # text before that, so it is the opt-out an absence-based law can honour, and
  # an all-night rotation script needs one: aborting on the first non-zero exit
  # would end the night at its first failed render.
  absent %r{scan:\s*intentional}
  # Only a shell shebang, not any shebang: a #!/usr/bin/env ruby script has no
  # set -euo pipefail to add, and flagging one is the false positive an
  # extensionless bin/ tool trips when its language cannot be read from a suffix.
  #
  # Two more shapes are not missing strict mode. `#!/bin/bash -e` sets it on the
  # shebang. An rc.d(8) script sources rc.subr, whose functions return non-zero
  # as control flow, so strict mode there stops the daemon script mid-check.
  detect do |text|
    text.match?(%r{\A#![^\n]*\b(?:sh|bash|zsh|ksh|dash)\b}) &&
      !text.match?(/^\s*set\s+-[eE]/) &&
      !text.match?(/\A#![^\n]*\s-[a-zA-Z]*e/) &&
      !text.match?(%r{^\s*\.\s+/etc/rc\.d/rc\.subr\b})
  end
  fix "Add 'set -euo pipefail' after shebang."
  bad <<~X
    #!/usr/bin/env zsh
    echo hi
  X
  good <<~X
    #!/usr/bin/env zsh
    # what this script does
    set -euo pipefail
  X
end
