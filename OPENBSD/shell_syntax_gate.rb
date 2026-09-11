#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse every shell script in this tree with the interpreter its shebang names.
#
# check-openbsd used to name two files by hand — vps_ci_all.sh and OPERATOR.sh —
# out of 43. The deploy path itself was not among them: bin/vps-deploy, vps_ci.sh
# and deploy_all.sh are what a deploy actually runs, so a syntax error in any of
# the three waited for a deploy to find it. resource_guard.sh is ksh, which a zsh
# list could not have covered at all.
#
# A hand-kept list is the wrong shape for this. A script's own shebang says which
# parser is authoritative for it, so reading that is both the complete set and the
# correct interpreter per file, and a script added tomorrow is covered by having a
# shebang rather than by somebody remembering this file.
#
# `-n` parses without executing, so this is safe to run anywhere, including on the
# box.

ROOT = File.expand_path("..", __dir__)
Dir.chdir(ROOT)

INTERPRETERS = %w[zsh ksh sh bash].freeze
SHEBANG = %r{\A\#!\s*(?:/usr/bin/env\s+)?(?:\S*/)?(#{INTERPRETERS.join('|')})\b}

# ksh -n on OpenBSD warns about `[[ -gt ]]` in scripts that are otherwise valid.
# The gate is about parse errors, not about a style the tree has settled on.
STYLE_WARNING = /obsolete/

def shebang_interpreter(path)
  first = File.open(path, &:readline)
  first[SHEBANG, 1]
rescue EOFError, ArgumentError
  nil
end

scripts = (Dir.glob("OPENBSD/**/*.sh") + Dir.glob("OPENBSD/bin/*") + Dir.glob("OPENBSD/usr/local/bin/*"))
          .uniq.sort.select { |path| File.file?(path) }

failures = []
checked = 0

scripts.each do |path|
  interpreter = shebang_interpreter(path)
  next unless interpreter

  checked += 1
  output = IO.popen([interpreter, "-n", path], err: [:child, :out], &:read)
  parsed = $?.success?
  complaints = output.lines.reject { |line| line.match?(STYLE_WARNING) }.join.strip
  next if parsed && complaints.empty?

  failures << "#{interpreter} -n #{path}\n#{complaints.empty? ? '  exited nonzero with no message' : complaints}"
end

if checked.zero?
  warn "shell_syntax: no script carried a shebang — the scan is broken, not the tree"
  exit 1
end

if failures.empty?
  puts "shell_syntax: #{checked} scripts parse"
  exit 0
end

warn "shell_syntax: #{failures.size} of #{checked} scripts do not parse"
failures.each { |failure| warn failure }
exit 1
