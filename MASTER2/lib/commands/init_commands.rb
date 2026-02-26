# frozen_string_literal: true

require "fileutils"

module MASTER
  module Commands
    # Generates CLAUDE.md and .github/copilot-instructions.md from current data inventory.
    module InitCommands
      INSTRUCTION_FILES = {
        "CLAUDE.md" => nil,
        ".github/copilot-instructions.md" => ".github",
      }.freeze

      def init_instructions(args)
        force = args.to_s.include?("--force")
        root  = Dir.pwd
        content = build_instructions

        INSTRUCTION_FILES.each do |rel, dir|
          path = File.join(root, rel)
          if File.exist?(path) && !force
            puts "  skip #{rel} (exists; use --force to overwrite)"
            next
          end
          FileUtils.mkdir_p(File.join(root, dir)) if dir
          File.write(path, content)
          puts "+ #{rel}"
        end

        Result.ok
      end

      private

      def build_instructions
        data_refs = data_file_refs
        <<~INST
          MASTER2 is the authoritative primary configuration for all AI-assisted work in this repository.

          #{data_refs}
          Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.

          Target platform: OpenBSD 7.8, Ruby 3.4, zsh. No python, bash, awk, sed, sudo. Use doas, rcctl, pkg_add.

          Shell & file ops: prefer zsh parameter expansion over sed/tr/awk; glob qualifiers over find; no external processes for string ops. Examples: ${var//old/new}, ${var:u}, **/*(.), *(Om[1]).

          Rails apps use Hotwire, Turbo, Stimulus, Solid Queue. Monolith first. Convention over configuration.

          Deploy scripts in deploy/ embed Ruby/Rails apps in zsh heredocs (single source of truth). Edit in-place, never extract.

          Anti-sprawl: never create summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md. Edit existing files directly.

          Communication style: OpenBSD dmesg-inspired. Terse, factual, evidence-based. No headlines, no bullet lists without content, no unnecessary tables.

          Run MASTER2 to validate changes: cd MASTER2 && bundle exec ruby bin/master scan <path>
        INST
      end

      DATA_FILE_DESCRIPTIONS = {
        "constitution.yml"      => "golden rule, convergence, anti-sprawl, self-protection, constraints",
        "axioms.yml"            => "69 axioms across 11 categories",
        "language_rules.yml"    => "ruby, rails, zsh, html, css, js detection rules + philosophy",
        "language_axioms.yml"   => "ruby, rails, zsh, html, css, js detection rules + philosophy",
        "platform.yml"          => "service management, forbidden commands, OpenBSD platform mappings",
        "openbsd_patterns.yml"  => "service management, forbidden commands, security",
        "zsh_patterns.yml"      => "banned commands, auto-remediation, token economics",
      }.freeze

      def data_file_refs
        data_dir = Paths.data
        DATA_FILE_DESCRIPTIONS.filter_map do |file, desc|
          next unless File.exist?(File.join(data_dir, file))

          "Read and follow MASTER2/data/#{file} (#{desc})."
        end.join("\n") + "\n"
      end
    end
  end
end
