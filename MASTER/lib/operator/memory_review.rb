# frozen_string_literal: true

require "master"
require "pathname"
require_relative "../cognition/outcome_model"
require_relative "../ground/memory"

module Operator
  # Explicit, evidence-backed memory review for the operator surface. It is
  # separate from slash commands so /fix remains the only ordinary slash verb
  # that writes. A review requires both the artifact digest and an affirmative
  # confirmation at the command line.
  class MemoryReview
    ROOT = File.expand_path("../../..", __dir__)
    USAGE = [
      "usage: bin/operator memory review <key> <confirmed|contradicted|uncertain|obsolete>",
      "--evidence <repo-relative-path> --sha256 <64-hex-digest> --reviewer <name> --confirm",
    ].join(" ").freeze
    MAX_KEY_CHARS = 200
    MAX_REVIEWER_CHARS = 120

    def self.run(argv, root: ROOT, memory: nil, out: $stdout, err: $stderr)
      new(root:, memory:, out:, err:).run(argv)
    end

    def initialize(root:, memory: nil, out: $stdout, err: $stderr)
      @root = File.realpath(root)
      @memory = memory
      @out = out
      @err = err
    end

    def run(argv)
      args = Array(argv).dup
      action = args.shift
      return refuse(USAGE, 64) unless action == "review"

      key = args.shift.to_s
      verdict = args.shift.to_s
      return refuse(USAGE, 64) if key.empty? || key.length > MAX_KEY_CHARS
      return refuse(USAGE, 64) if key.match?(/[\u0000-\u001f\u007f]/)

      options = parse_options(args)
      return refuse(USAGE, 64) unless options
      return refuse("explicit --confirm is required before memory is changed", 64) unless options[:confirm]

      reviewer = options[:reviewer].to_s.strip
      return refuse("reviewer is required", 64) if reviewer.empty?
      return refuse("reviewer exceeds #{MAX_REVIEWER_CHARS} characters", 64) if reviewer.length > MAX_REVIEWER_CHARS

      evidence_path = options[:evidence].to_s
      digest = options[:sha256].to_s.downcase
      return refuse("evidence path must be repository-relative", 64) if evidence_path.empty? || Pathname.new(evidence_path).absolute?
      return refuse("SHA-256 must contain 64 hexadecimal characters", 64) unless digest.match?(/\A[0-9a-f]{64}\z/)

      # OutcomeModel verifies containment, symlinks, file size and digest before
      # returning content. No file is read by this command before that boundary.
      evidence = Master::Cognition::OutcomeModel.validate_evidence!(
        { source: evidence_path, sha256: digest },
        root: @root,
      )
      memory = @memory || Master::Ground::Memory.new(root: File.join(@root, "MASTER"))
      reviewed = memory.review(
        key,
        verdict:,
        evidence: { source: evidence.fetch("source"), content: evidence.fetch("content"), sha256: evidence.fetch("sha256") },
        reviewer:,
      )
      return refuse("no reviewable memory entry named #{key.inspect}", 1) unless reviewed

      @out.puts(
        "memory0: reviewed #{key} as #{reviewed.fetch("status")} by #{reviewed.dig("reviews")&.last&.fetch("reviewer")} " \
        "evidence=#{evidence.fetch("source")} sha256=#{evidence.fetch("sha256")}",
      )
      0
    rescue ArgumentError, SystemCallError, IOError => e
      refuse("review refused: #{e.class}: #{e.message}", 2)
    rescue StandardError => e
      refuse("review failed: #{e.class}: #{e.message}", 1)
    end

    private

    def parse_options(args)
      options = {}
      until args.empty?
        flag = args.shift
        case flag
        when "--confirm"
          return if options[:confirm]

          options[:confirm] = true
        when "--evidence", "--sha256", "--reviewer"
          key = { "--evidence" => :evidence, "--sha256" => :sha256, "--reviewer" => :reviewer }.fetch(flag)
          return if options.key?(key) || args.empty? || args.first.start_with?("--")

          options[key] = args.shift
        else
          return
        end
      end
      return unless %i[evidence sha256 reviewer].all? { |key| options.key?(key) }

      options
    end

    def refuse(message, status)
      @err.puts("memory0: failed, #{message}")
      status
    end
  end
end
