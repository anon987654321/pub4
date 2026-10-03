# frozen_string_literal: true

# law/prose.rb — the prose laws, generated one pair per natural language.
#
# EN_DASH_RANGE lives once, in the registry (cosmetic_rules.rb): it also
# covers yaml and html, skips YAML list items and rule-id lines, and —
# decisive here — `prose` is not a language FILE_LANGUAGE_MAP produces, so
# half this law's declared scope never matched a file (Bringhurst's credit
# rides with the registry version).
#
# Strunk describes a shape, not a list of English words: an intensifier that
# adds emphasis and no information, a passive that hides its actor. Any language
# with those has its own words for them. Holding the words in the detector made
# these two English-only by accident, so the vocabulary, the senses to keep, the
# passive's shape and the fixtures all live in data/rules.yml under `prose:`,
# and this file turns each entry into a pair of laws. A second language is a
# data edit.
#
# `spoken_in` scopes each language to the files it is written in, and that
# scoping is what makes the whole design safe: Norwegian `bare` (only) is an
# English word this tree uses constantly — "a bare regex", "bare true" — so a
# vocabulary let loose outside its own files returns nothing but noise.
#
# A prose law also has to reach prose, and both of these reached the opposite of
# it. `reads_comments` defaults to false, which means considered_text blanks
# every comment before the detector runs, so in Ruby they saw the code and
# nothing else: every hit was a string literal or an identifier — `raise
# "#{path} is untracked"`, "Solid Queue must be enabled", a <<~JS heredoc. Not
# one was a sentence anybody wrote as prose. Reaching comments is half of it;
# the code lines are still in the text, which is what `reads:` settles per
# language.

module Law
  module Prose
    # Through the accessor, not a second YAML.load_file of rules.yml. A data
    # file with two loading paths is how the two drift, which is what
    # test_reader_singularity ratchets against.
    CONFIG = Master.law("prose").freeze

    # A comment that names a word in backticks is discussing the word, not using
    # it — the same distinction Law.conduct draws for a law that has to judge
    # law/ itself. Without this, these laws fire on the paragraphs explaining
    # them.
    QUOTED = /`[^`]*`/
    LEADER = /\A\s*#/
    CODE = /[=(){}\[\];|"']|\b(?:def|end|class|module|return|require)\b/
    # A locale file's key is a symbol, not a sentence.
    KEY = /\A\s*(?:-\s*)?[\w.]+:\s*/

    # The prose in a line, or nil where the line carries none. Markdown has no
    # comment leader to key on, so `comments` also takes a line with no code
    # punctuation — conservative, and it passes over a prose sentence holding a
    # quote rather than risk judging a fenced code block as English.
    def self.said(line, reads)
      text = line.gsub(QUOTED) { |match| " " * match.length }
      case reads
      when "comments" then text.match?(LEADER) || !text.match?(CODE) ? text : nil
      when "values" then text.sub(KEY, "")
      end
    end

    def self.any(patterns) = Regexp.union(patterns.map { |pattern| Regexp.new(pattern) })

    def self.words(list) = /\b(?:#{list.map { |word| Regexp.escape(word) }.join('|')})\b/
  end
end

Law::Prose::CONFIG.each_value do |language|
  reads = language["reads"]
  scope = Regexp.new(language["spoken_in"])
  tongue = language["file_languages"].map(&:to_sym)

  # Most of the words a leech list attracts are only sometimes leeches, and the
  # other sense is load-bearing every time. Judged over 172 English hits:
  #
  # `actually` is never an intensifier here. It is contrastive, setting what is
  # against what was claimed — "the dmesg stream the operator actually reads",
  # "no process was ever actually listening on the port". That distinction is
  # this repo's recurring subject, so the word carries the sentence. All 85 hits
  # were that, and it stays out of the list for the same reason `literally`
  # does. Bokmål's `egentlig` and `faktisk` are held out on the same grounds.
  #
  # `just` has three senses and one is a leech: moments ago fixes a tense,
  # `just as` compares, `not just` negates, and merely is what is left. `very` is two
  # words — the intensifier grades an adjective, the determiner picks a thing
  # out ("this very rule's own fixture") and is the sentence's point.
  #
  # `rather` was the instrument rather than the prose: all 16 hits were a
  # "rather than" broken across two comment lines with `than` opening the next,
  # which a line-scoped detector cannot see. In its leech sense it qualifies
  # what follows, so it never ends a line — trailing, it is the wrap.
  keep = Law::Prose.any(language["keep"])
  leeches = Law::Prose.words(language["leeches"])
  qualifiers = language["fixtures"]["qualifiers"]

  Law.define(language["ids"]["qualifiers"].to_sym) do
    source "Strunk, Elements of Style (1918) — the leech words"
    severity :warn
    languages tongue
    path scope
    reads_comments true
    detect do |line|
      said = Law::Prose.said(line, reads)
      next false unless said
      next false if said.match?(keep)

      said.match?(leeches)
    end
    fix "Delete the qualifier; let the verb or noun carry the weight."
    bad qualifiers["bad"]
    good qualifiers["good"]
  end

  # Strunk carves his own rule down: the agentless passive is right where the
  # actor is unknown or beside the point. This tree leans on it to narrate
  # evidence — "16 files were deleted", "the parameter has been inert since it
  # was added" — where naming an actor would be an invention, and 158 of 160
  # hits were that. The defect is the passive that names its agent and puts it
  # last, so the agent has to sit directly after the participle: an agent marker
  # further along the line belongs to a different clause.
  shape = language["passive"]
  hidden = /\b#{shape['auxiliary']}\s+#{shape['participle']}\s+#{shape['agent']}\s+\w/
  passive = language["fixtures"]["passive"]

  Law.define(language["ids"]["passive"].to_sym) do
    source "Strunk, Elements of Style (1918) Rule 10 — use the active voice"
    severity :info
    languages tongue
    path scope
    reads_comments true
    detect do |line|
      said = Law::Prose.said(line, reads)
      next false unless said

      said.match?(hidden)
    end
    fix "Recast active: 'the bug was fixed by X' -> 'X fixed the bug'."
    bad passive["bad"]
    good passive["good"]
  end
end
