#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

# SWEEP_ROOT, not ROOT. This file is required by test/test_security_sweep.rb,
# and 25 files in this repo define a bare top-level ROOT, each pointing at a
# different tree. In one `rake test` process STUDIO/dilla/dilla.rb also defines
# one, so the two collided: Ruby warned and let the second assignment win, which
# means whichever loaded last silently gave the other the wrong repo root.
# The warning was the only thing standing between that and a sweep of the wrong
# tree reporting clean. See TODO.md, "Top-level ROOT".
SWEEP_ROOT = File.expand_path("../..", __dir__)
QUARANTINE = File.join(SWEEP_ROOT, "OPENBSD", "quarantine", "virus_museum")

SECRET_PATTERNS = [
  /sk-[A-Za-z0-9_\-]{16,}/,
  /sk-ant-[A-Za-z0-9_\-]{16,}/,
  /AKIA[0-9A-Z]{16}/,
  /-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/,
  /(?<![a-z_])api_key\s*[:=]\s*["'][^"']{8,}["']/i,
].freeze

# The password rule needs the value, not just a match. As a bare pattern —
# /password\s*[:=]\s*["'][^"'\[\]]{8,}["']/i — it flagged sixteen i18n strings
# across three apps ("Glemt passord?", "Confirm password", "Update your
# password"), so `bin/check --profile=contributor` and the operator profile were
# both failing on translated UI copy. A gate whose failure is always noise is a
# gate people learn to skip.
PASSWORD_ASSIGNMENT = /(?<![a-z_])password\s*[:=]\s*["']([^"'\[\]]{8,})["']/i
PLACEHOLDERS = /\A(?:password123|changeme|example|secret|\[your password\])\z/i
# Prose, not a credential: one word or hyphenated words with no digit or symbol.
PROSE_VALUE = /\A[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\-]*[?.!]?\z/
# A value that is nothing but an indirection names where the credential comes
# from; the credential itself lives in the environment or a locale file.
# RAILS/gates/data/flows.yml posts "$FLOW_AMBER_PASSWORD" to a login form, and a
# sweep that reads a variable name as the secret it stands for is the same
# always-noise failure the i18n strings above already caused once.
INDIRECTION = /\A(?:\$\{?[A-Za-z_]\w*\}?|%\{[^}]+\}|<%=[^%]*%>|\#\{[^}]+\})\z/

def secretish_password?(value)
  return false if value.match?(/\s/)          # "Forgot password?" — copy, not a credential
  return false if value.match?(PLACEHOLDERS)
  return false if value.match?(INDIRECTION)
  return false if value.match?(PROSE_VALUE) && value.length < 16

  true
end

def password_hits(body)
  body.scan(PASSWORD_ASSIGNMENT).flatten.select { |value| secretish_password?(value) }
end

SKIP_PATH_RE = %r{
  \A(?:OPENBSD/quarantine/|
  OPENBSD/archive/recovery/references/|
  .*/test/|
  .*/tests/|
  MASTER/data/eval_cases\.yml|
  MASTER/test/)
}x.freeze

TRACKED_DENY_GLOBS = [
  "RAILS/*/config/master.key",
  "RAILS/*/storage/**/*.sqlite3",
  "RAILS/*/db/**/*.sqlite3",
  "**/.env",
  "**/credentials/*.key",
  # CLAUDE.md's never-commit list, as a check rather than a sentence. These are
  # gitignored, and .gitignore is exactly what failed for the seven master.key
  # blobs still readable in this repo's history: a pattern stops a mistake only
  # until someone adds a path explicitly. START_HERE.md "Do Not Touch" 2 names
  # this sweep as its gate, so the claim now has a reader.
  "MASTER/knowledge/**",
  "MASTER/output/**",
  "**/.master/**",
].freeze

# MASTER/law/*.rb is the instrument, not the subject. Every Law.define carries a
# `bad` fixture that must violate the rule it declares, so SECRET_PROXIMITY's
# reads `api_key = 'sk_live_abcdef123456'` and this sweep called it a finding —
# the same shape as scanning test/, which SKIP_PATH_RE already refuses for the
# same reason.
#
# The tree is not skipped wholesale, because a real credential committed beside
# a fixture would then be the one thing here nobody is looking at. Only the two
# declared fixture lines are dropped; everything else in the file is scanned.
LAW_FIXTURE_RE = /^[ \t]*(?:bad|good)[ \t]+["'].*$/.freeze

def strip_law_fixtures(path, body)
  return body unless path.start_with?("MASTER/law/")

  body.gsub(LAW_FIXTURE_RE, "")
end

def git_ls_files(pattern)
  out, status = Open3.capture2("git", "-C", SWEEP_ROOT, "ls-files", pattern)
  status.success? ? out.lines.map(&:chomp).reject(&:empty?) : []
end

def scan_tracked_secrets
  hits = []
  git_ls_files(".").each do |path|
    next if path.match?(SKIP_PATH_RE)
    next if path.end_with?("/db/seeds.rb")
    next unless File.file?(File.join(SWEEP_ROOT, path))
    next if File.size(File.join(SWEEP_ROOT, path)) > 512_000

    body = File.read(File.join(SWEEP_ROOT, path), mode: "rb").force_encoding(Encoding::UTF_8)
    next unless body.valid_encoding?

    body = strip_law_fixtures(path, body)

    SECRET_PATTERNS.each do |pattern|
      next if pattern.source.include?("api_key") && body.include?("API_KEY_PROVIDERS")

      hits << "#{path}: #{pattern}" if body.match?(pattern)
    end

    found = password_hits(body)
    hits << "#{path}: password assignment (#{found.size}): #{found.first(3).join(", ")}" if found.any?
  end
  hits
end

def sweep
  failures = []

  TRACKED_DENY_GLOBS.each do |pattern|
    tracked = git_ls_files(pattern)
    failures.concat(tracked.map { |path| "tracked secret artifact: #{path}" })
  end

  failures.concat(scan_tracked_secrets)

  failures << "virus museum README missing" unless File.file?(File.join(QUARANTINE, "README.md"))

  quarantine_files = git_ls_files("OPENBSD/quarantine/virus_museum")
  bad_ext = quarantine_files.reject { |path| path.end_with?(".txt") || path.end_with?("README.md") }
  failures.concat(bad_ext.map { |path| "virus museum non-text file: #{path}" })

  mode_lines, = Open3.capture2("git", "-C", SWEEP_ROOT, "ls-files", "-s", "OPENBSD/quarantine/virus_museum")
  mode_lines.lines.each do |line|
    mode, _type, _sha, _stage, path = line.split(/\s+/, 5)
    failures << "virus museum executable: #{path}" if mode && mode != "100644"
  end

  [failures, quarantine_files.size]
end

# Guarded so test/test_security_sweep.rb can require this file and exercise the
# password predicate directly. Without it, the only way to test the rule was to
# run the whole sweep and read its output — which is how the rule shipped with a
# sixteen-hit false-positive rate on translated UI copy.
if $PROGRAM_NAME == __FILE__
  failures, samples = sweep

  if failures.any?
    warn "Security sweep failures:"
    failures.each { |failure| warn "  - #{failure}" }
    exit 1
  end

  puts "Security sweep passed (#{samples} quarantine samples, 0 tracked secrets)."
end
