# frozen_string_literal: true

module Master
  module Fix
    # Asks the model whether a file's name says what the file is, and if not
    # what it should be called; then asks it, in a second and hostile turn,
    # whether the proposed name is actually better. A rename changes every
    # reader's map of the tree, so a name has to survive being attacked before
    # FileRename moves anything.
    class NameReview
      PROPOSE = <<~TEXT
        A file's name should tell a reader what the file is for without opening it.
        Judge this one. Prefer KEEP: a name that is merely unfamiliar, or one the
        rest of the tree already uses as a convention, stays.

        Path: %<path>s
        Its neighbours: %<siblings>s
        Why it is being reviewed: %<reason>s
        Its first lines:
        %<head>s

        Answer with exactly one line and nothing else:
        KEEP
        or
        RENAME: <new file name>
        The new name stays in the same directory with the same extension(s), is
        lowercase snake_case, and keeps a leading underscore if the old one has one.
      TEXT

      ATTACK = <<~TEXT
        Proposed rename: %<from>s -> %<to>s, beside %<siblings>s.
        Attack it. Does the new name mislead about what the file holds, blur it with
        a neighbour, drop information a reader relied on, or only restyle a name
        that was already clear? Rename only when a newcomer would find the file
        faster by the new name.
        Answer with exactly one line: APPROVE, or REJECT: <reason>.
      TEXT

      NAME = /\A(_?)[a-z][a-z0-9_]*((?:\.[a-z0-9]+)+)\z/

      def initialize(agent:)
        @agent = agent
      end

      # The approved new basename, or nil to keep the file as it is.
      def propose(path, reason:)
        answer = ask(format(PROPOSE, path:, siblings: siblings(path), reason:, head: head(path)))
        candidate = answer[/\ARENAME:\s*(\S+)\s*\z/, 1]
        return unless candidate && valid?(path, candidate)

        verdict = ask(format(ATTACK, from: File.basename(path), to: candidate, siblings: siblings(path)))
        candidate if verdict.start_with?("APPROVE")
      end

      # Same underscore, same extensions, a real change, and no collision.
      def valid?(path, candidate)
        old = File.basename(path).match(NAME)
        new = candidate.match(NAME)
        return false unless old && new && candidate != File.basename(path)

        old[1] == new[1] && old[2] == new[2] && !File.exist?(File.join(File.dirname(path), candidate))
      end

      private

      def ask(prompt)
        @agent.ask(prompt, operation: :name_review).to_s.strip.lines.first.to_s.strip
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.name_review")
        ""
      end

      def siblings(path)
        Dir.children(File.dirname(path)).reject { |name| name == File.basename(path) }.sort.first(30).join(", ")
      end

      def head(path) = File.foreach(path).first(60).join
    end
  end
end
