# frozen_string_literal: true

require "fileutils"
require "pathname"

module MASTER
  module Commands
    # Generates CLAUDE.md and .github/copilot-instructions.md from the live data/ inventory.
    module InitCommands
      TARGETS = [
        ["CLAUDE.md",                       nil      ],
        [".github/copilot-instructions.md", ".github"],
      ].freeze

      DATA_REFS = {
        "constitution.yml"    => "golden rule, convergence, anti-sprawl, constraints",
        "axioms.yml"          => "69 axioms across 11 categories",
        "language_rules.yml"  => "ruby, rails, zsh, html, css, js rules + philosophy",
        "language_axioms.yml" => "ruby, rails, zsh, html, css, js rules + philosophy",
        "platform.yml"        => "OpenBSD service management, forbidden commands",
        "openbsd_patterns.yml"=> "OpenBSD service management, forbidden commands",
        "zsh_patterns.yml"    => "banned shell commands, auto-remediation",
      }.freeze

      def init_instructions(force: false)
        root    = Pathname(Dir.pwd)
        content = instructions_content

        TARGETS.each do |rel, dir|
          dest = root / rel
          next if dest.exist? && !force

          FileUtils.mkdir_p(root / dir) if dir
          dest.write(content)
          puts "+ #{rel}"
        end

        Result.ok
      end

      private

      def instructions_content
        data = Pathname(Paths.data)
        refs = DATA_REFS.filter_map do |file, desc|
          "Read and follow MASTER2/data/#{file} (#{desc})." if (data / file).exist?
        end.join("\n")

        <<~MD
          MASTER2 is the authoritative primary configuration for all AI-assisted work in this repository.

          #{refs}

          Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.
          Anti-sprawl: never create summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md.
          Style: OpenBSD dmesg. Terse, factual, evidence-based. No filler, no hedging.

          Validate: cd MASTER2 && bundle exec ruby bin/master scan <path>
        MD
      end
    end
  end
end
