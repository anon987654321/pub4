# frozen_string_literal: true

module MASTER
  # Learnings - Captures insights from sessions for future use
  # When something is discovered (bug pattern, good practice, UX insight),
  # it gets recorded here so MASTER can apply it automatically next time
  module Learnings
    extend self

    CATEGORIES = %i[bug_pattern good_practice ux_insight architecture security].freeze

    def file_path
      File.join(Paths.var, "learnings.jsonl")
    end

    def record(category:, pattern:, description:, example: nil, severity: :info)
      raise ArgumentError, "Invalid category" unless CATEGORIES.include?(category)

      learning = {
        id: SecureRandom.hex(8),
        category: category,
        pattern: pattern,
        description: description,
        example: example,
        severity: severity,
        discovered_at: Time.now.utc.iso8601,
        applied_count: 0,
      }

      File.open(file_path, "a") { |f| f.puts(JSON.generate(learning)) }
      learning
    end

    def all
      return [] unless File.exist?(file_path)

      File.readlines(file_path).filter_map do |line|
        JSON.parse(line.strip, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end
    end

    def by_category(category)
      all.select { |l| l[:category] == category }
    end

    def apply_to(code)
      learnings = by_category(:bug_pattern)
      issues = []

      learnings.each do |learning|
        next unless learning[:pattern]

        begin
          regex = Regexp.new(learning[:pattern])
          if code.match?(regex)
            issues << {
              learning_id: learning[:id],
              description: learning[:description],
              severity: learning[:severity],
            }
            increment_applied(learning[:id])
          end
        rescue RegexpError
          # Invalid pattern, skip
        end
      end

      issues
    end

    def increment_applied(id)
      learnings = all
      learning = learnings.find { |l| l[:id] == id }
      return unless learning

      learning[:applied_count] += 1
      rewrite(learnings)
    end

    def seed_from_session
      # Learnings discovered in the Feb 7 2026 deep analysis session
      [
        {
          category: :bug_pattern,
          pattern: 'DB\.setup(?!\s*\()',
          description: "DB.setup without MASTER:: prefix in bin/ scripts",
          example: "bin/master line 5: DB.setup should be MASTER::DB.setup",
          severity: :critical,
        },
        {
          category: :bug_pattern,
          pattern: '\.start_with\?\(["\']',
          description: "Calling .start_with? on value that might be a symbol",
          example: "SHORTCUTS[input] returns symbol, then .start_with? crashes",
          severity: :critical,
        },
        {
          category: :bug_pattern,
          pattern: '\.pop\(\d+\)(?!.*@dirty)',
          description: "Mutating collection without setting dirty flag",
          example: "session.history.pop(2) needs session.@dirty = true",
          severity: :major,
        },
        {
          category: :bug_pattern,
          pattern: '\["[a-z_]+"\]\s*\|\|\s*\[:[a-z_]+\]',
          description: "Mixed string/symbol hash access - use symbolize_names",
          example: 'row["model"] || row[:model] -> just use row[:model]',
          severity: :minor,
        },
        {
          category: :good_practice,
          pattern: "symbolize_names:\\s*true",
          description: "Always use symbolize_names: true with JSON.parse",
          severity: :info,
        },
        {
          category: :ux_insight,
          pattern: nil,
          description: "Show context % in prompt when > 5%",
          example: "master[strong|$9.50|ctx:12%]$",
          severity: :info,
        },
        {
          category: :ux_insight,
          pattern: nil,
          description: "Provide 'did you mean?' for typos within edit distance 2",
          severity: :info,
        },
        {
          category: :ux_insight,
          pattern: nil,
          description: "Auto-save session every 5 messages AND on Ctrl+C",
          severity: :info,
        },
        {
          category: :security,
          pattern: 'rm\s+-rf?\s+/',
          description: "Block destructive shell commands in Guard stage",
          severity: :critical,
        },
        {
          category: :architecture,
          pattern: nil,
          description: "Two session systems exist (Memory JSON, DB JSONL) - Session uses Memory",
          severity: :info,
        },
      ].each do |learning|
        record(**learning) unless exists?(learning[:description])
      end
    end

    private

    def exists?(description)
      all.any? { |l| l[:description] == description }
    end

    def rewrite(learnings)
      File.open(file_path, "w") do |f|
        learnings.each { |l| f.puts(JSON.generate(l)) }
      end
    end
  end
end
