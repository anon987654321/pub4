# frozen_string_literal: true

# Secret redaction for sync.rb, the return leg of the drift gate.
#
# The patterns are a floor, not a ceiling. A secret whose name carries no
# `_KEY=`-shaped suffix, or whose value does not start with the one prefix a
# pattern pinned, mirrored into git verbatim — which is how a shared checkout
# leaks. The residue audit closes that direction: after redaction, any line
# still carrying a secret-shaped name with a non-empty value refuses the file
# instead of writing it, so the operator extends the patterns rather than
# discovering the gap in a pushed commit.
module SecretRedaction
  PLACEHOLDER = "__REDACTED__".freeze

  SECRET_PATTERNS = [
    /(_API_KEY=)\S+/,
    # Any *_KEY= value, not only sk-prefixed ones: r8_ and other provider
    # prefixes passed the old sk- guard and mirrored unredacted.
    /(_KEY=)\S+/,
    /(SECRET_KEY_BASE=)[a-f0-9]{32,}/,
    /(_TOKEN=)\S+/,
    /(_PASSWORD=)\S+/,
    /(_SECRET=)\S+/,
  ].freeze

  # Names that carry secrets but match no value-shaped pattern above — bare
  # `smtp_url=`, yaml `password:`. Matches key/token/secret/password/passphrase
  # inside a larger word, then an `=` or `:` with a non-empty value. Lines
  # already carrying the placeholder are skipped, so a redacted line never
  # refuses its own file.
  RESIDUE_PATTERN =
    /\b[A-Za-z0-9_-]*(?:key|token|secret|password|passphrase)[A-Za-z0-9_-]*\s*[=:]\s*\S+/i.freeze

  # Credentials embedded in a URL — `smtp://user:pass@mail` — carry no
  # secret-shaped name, so the name audit above is blind to them.
  RESIDUE_URI_PATTERN = /[a-z][a-z0-9+.-]*:\/\/\S+:\S+@/i.freeze

  def self.redact(body)
    SECRET_PATTERNS.inject(body) { |acc, pat| acc.gsub(pat, '\1' + PLACEHOLDER) }
  end

  # The lines that still look secret after redaction, stripped for the
  # refusal message. Empty means the file is safe to mirror.
  def self.residue(body)
    redacted = redact(body)
    redacted.lines.grep_v(/#{PLACEHOLDER}/).grep(Regexp.union(RESIDUE_PATTERN, RESIDUE_URI_PATTERN)).map(&:strip)
  end
end
