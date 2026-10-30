# frozen_string_literal: true

require "set"

module Law
  # A `detect` regex reports a line and the Law's fix text; it has no account of
  # its own, so `message` and `detail` are nil.
  Finding = Data.define(:id, :file, :line, :text) do
    def message = nil
    def detail = nil
  end

  # A `check` or detector class reports the scanner finding it built (`detail`),
  # whose line and message are its own account of what it saw.
  CheckFinding = Data.define(:id, :file, :text, :detail) do
    def line = Master::Review::Scan::Finding.read(detail, :line).to_i
    def message = Master::Review::Scan::Finding.read(detail, :message)
  end

  # What every law asks of one subject, worked out once. The bridge hands the
  # same text to each of a hundred laws in turn, and each re-split it into
  # lines, re-found its comment spans and tested every line for the intentional
  # marker; on a large stylesheet that was most of a scan. The view is held per
  # thread for the text it was built from, so a different text or file rebuilds
  # it and no law sees another subject's lines.
  class SubjectView
    INTENTIONAL = /scan:\s*intentional\b/

    attr_reader :lines, :skipped, :intentional

    def initialize(text:, file:, leaders:, continued:)
      @text = text
      @file = file
      @size = text.bytesize
      @lines = text.each_line.to_a
      @intentional = Set.new
      @skipped = Set.new(continued)
      @lines.each_with_index do |line, index|
        @intentional << index if line.match?(INTENTIONAL)
        @skipped << index if @intentional.include?(index) || leaders.any? { |leader| line.lstrip.start_with?(leader) }
      end
      @continued = continued
      @considered = {}
    end

    def fresh?(text, file) = @text.equal?(text) && @file == file && @size == text.bytesize

    def continued?(index) = @continued.include?(index)

    def considered(reads_comments) = @considered.fetch(reads_comments) { @considered[reads_comments] = yield }
  end

  # A line-scoped detector reads code, and a comment naming a forbidden
  # construct is prose about it, not an instance of it — "# a bare rescue"
  # became an error-severity finding when FAIL_VISIBLY moved here from the
  # yaml bridge, which had learned this once already. Comment-leading lines
  # are skipped for the file's own comment syntax; a rule whose subject IS
  # comments (WHY_NOT_WHAT, TYPOGRAPHY_DISCIPLINE) declares `reads_comments
  # true`. Fixtures prove with file "-", which has no extension and so no
  # comment syntax — a fixture is always read whole.
  # Keyed by language rather than by extension, because an extension table here
  # is a second copy of FILE_LANGUAGE_MAP that has to agree with it and does
  # not. Adding .ksh, .ru and .mjs to that map made three more file types
  # readable and left their comments unblanked, so DOLLAR_PAREN read the prose
  # backticks in a ksh comment — `keepenv`, `sysctl | awk` — as command
  # substitution. One table, and a new extension inherits its language's
  # comment syntax for free.
  LANGUAGE_COMMENT_LEADERS = {
    "ruby" => ["#"], "yaml" => ["#"], "zsh" => ["#"],
    "javascript" => ["//", "/*"],
    "css" => ["/*"], "scss" => ["//", "/*"],
    "html" => ["<!--"]
  }.freeze

  # ERB is html by language and carries Ruby's comment tag as well, which is the
  # one case the language alone does not answer.
  EXTENSION_COMMENT_LEADERS = { ".erb" => ["<%#"] }.freeze

  def self.comment_leaders(file)
    language = Master.language_for(file)
    LANGUAGE_COMMENT_LEADERS.fetch(language, []) +
      EXTENSION_COMMENT_LEADERS.fetch(File.extname(file).downcase, [])
  end
end
