# frozen_string_literal: true

require_relative "../ground/commit_format"

module Master
  module Fix
    # Every commit /fix makes, in the shape data/commit_format.yml sets: a capitalised subject of at
    # most 72 characters with no type prefix and no full stop, a body saying what changed and why,
    # and the Co-authored-by trailer GitOperations#commit adds. /fix wrote "Fix_loop: fast-fix
    # [pass 1]" and "ABC_SIZE in baymard_law.rb" with a one-line body or none.
    #
    # The checker is Ground::CommitFormat, the one the commit-msg hook asks; this adds only what a
    # /fix commit owes beyond it, a body, and the MARKER line that tells /fix's commits from the
    # other writers who share the trailer.
    module CommitMessage
      MARKER = "Written by MASTER /fix"
      # "fix_loop:", "stream_fix:": a label the type-prefix rule does not know, but one all the same.
      PSEUDO_PREFIX = /\A[A-Za-z]+_[A-Za-z_]+:/

      module_function

      def compose(subject, what:, why:, details: [])
        body = wrap([sentence(what), sentence(why)].join(" "))
        extra = details.empty? ? [] : ["", *details]
        check!([fit(subject), "", body, *extra, "", MARKER].join("\n"))
      end

      # One /fix repair of one finding. The finding's own words stay out: the committer's
      # preserve_user_intent check reads the message, and a finding that says "extract" would read as a
      # refactor the repair never claimed.
      def repair(law:, file:, line:)
        laws = law.to_s.split("+")
        noun = laws.size == 1 ? "finding" : "findings"
        compose(repair_subject(laws, File.basename(file.to_s)),
                what: "/fix rewrote #{relative(file)} near line #{line} to clear its #{listed(laws)} #{noun}",
                why: "The change passed the scope check, the rescan, the file's tests and the reviewer")
      end

      # The file name always survives: a subject cut to 72 characters lost it and ended on "in".
      def repair_subject(laws, name)
        limit = Master::Ground::CommitFormat.max_chars
        full = "Repair #{listed(laws)} in #{name}"
        return full if full.size <= limit

        short = "Repair #{laws.first} and #{laws.size - 1} more in #{name}"
        laws.size > 1 && short.size <= limit ? short : "Repair #{name}"
      end

      def listed(laws) = laws.size <= 2 ? laws.join(" and ") : "#{laws[0..-2].join(", ")} and #{laws.last}"

      # The body names the file from the repository root, not the checkout it ran in.
      def relative(file)
        root = defined?(Master::REPO_ROOT) ? Master::REPO_ROOT : Dir.pwd
        File.expand_path(file.to_s).delete_prefix("#{File.expand_path(root)}/")
      end

      PASS_SHAPES = {
        clean: ["Deliver the files /fix pass %d left clean", "Commits what pass %d changed",
                "the pass's checks found no violation left in those files"],
        pass: ["Deliver the repairs of /fix pass %d", "Commits the repairs pass %d made and verified",
               "the pass ended with them checked and not yet committed"],
        fast: ["Apply the deterministic fixes of /fix pass %d", "Commits the RuboCop and AST corrections of pass %d",
               "each file kept parses and its mapped test passes"],
        llm: ["Deliver the model repairs of /fix pass %d",
              "Commits the model repairs of pass %d its per-fix commits left",
              "each passed the scope check, the rescan and the reviewer"],
        stream: ["Deliver the streamed repairs of /fix pass %d", "Commits the repairs pass %d made while it scanned",
                 "each passed the scope check, the rescan and the reviewer"],
      }.freeze

      # A pass-level delivery: kind is one of PASS_SHAPES.
      def pass(kind, number)
        subject, what, why = PASS_SHAPES.fetch(kind)
        compose(format(subject, number), what: format(what, number), why: "It is delivered because #{why}")
      end

      # The message, or an ArgumentError naming every rule it breaks.
      def check!(text)
        found = problems(text)
        return text if found.empty?

        raise ArgumentError, "a /fix commit message breaks data/commit_format.yml: #{found.join("; ")}"

      end

      def problems(text)
        lines = text.to_s.strip.lines.map(&:chomp)
        found = Master::Ground::CommitFormat.problems("#{text.to_s.strip}\n\n#{Master::Core::World::COMMIT_TRAILER}")
        label = lines.first.to_s[PSEUDO_PREFIX]
        found << "the subject starts with a label (#{label})" if label
        found << "a /fix commit needs a body saying what changed and why" unless body?(lines)
        found << "a /fix commit carries the line #{MARKER.inspect}" unless lines.include?(MARKER)
        found
      end

      def own?(message) = message.to_s.lines.map(&:chomp).include?(MARKER)

      def body?(lines) = lines.drop(2).any? { |line| !line.strip.empty? && line != MARKER }

      def sentence(text)
        said = plain(text).strip
        said.match?(/[.!?]\z/) ? said : "#{said}."
      end

      # Finding messages carry typographic dashes; a commit body is plain text.
      def plain(text) = text.to_s.gsub(/\s*[\u2013\u2014]\s*/, ", ").gsub(/\s+/, " ")

      # A body reads at 72 columns, as git log shows it.
      def wrap(text) = text.scan(/\S.{0,71}(?=\s|\z)|\S+/).join("\n")

      def fit(subject)
        text = Master::Ground::CommitFormat.normalize_subject(subject)
        limit = Master::Ground::CommitFormat.max_chars
        return text if text.size <= limit

        text[0, limit + 1].sub(/\s+\S*\z/, "")
      end
    end
  end
end
