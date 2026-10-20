# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Cognition

    DiscourseHit = Struct.new(:rule, :marker, :line, :from, :speaker, :text, keyword_init: true) do
      def to = from + marker.length
      def span = text[from, marker.length]
      def observation(counter:, confidence:, alternatives:, limit:)
        DiscourseObserver::Observation.new(rule:, line:, from:, to:, span:, speaker:, confidence:, supporting: [marker],
                        counter_evidence: counter, alternatives:, limit:, statement:)
      end

      def statement = "wording consistent with #{rule.tr("_", " ")}; not a statement about intent or character"
    end

    # Points at spans of a transcript that match a catalogued speech pattern. It reads text it is
    # handed and nothing else: no audio, no microphone, no network. Each observation names the exact
    # span, the rule that matched, the evidence for and against, and other explanations, and carries a
    # confidence capped by what wording alone can show. It never says what anyone intends or is, and
    # every call is appended to an audit trail the operator can read.
    class DiscourseObserver
      Observation = Data.define(:rule, :line, :from, :to, :span, :speaker, :confidence, :supporting,
                                :counter_evidence, :alternatives, :limit, :statement)

      CATALOGUE = File.expand_path("../../data/discourse_patterns.yml", __dir__)
      SPEAKER = /\A\s*([A-Za-zÆØÅæøå][\wÆØÅæøå .'-]{0,30}):\s+(.*)\z/

      def initialize(catalogue: Master.load_yaml(CATALOGUE), audit_path: nil)
        @catalogue = catalogue
        @audit_path = audit_path
      end

      def version = @catalogue.fetch("version")

      # Observations for a transcript, in the order they occur. An empty list means no catalogued
      # wording was found, which says nothing about whether anything else is going on.
      def observe(transcript)
        found = transcript.to_s.lines.each_with_index.flat_map { |line, index| observe_line(line.chomp, index + 1) }
        audit(found)
        found
      end

      private

      def observe_line(line, number)
        speaker, text = split_speaker(line)
        @catalogue.fetch("markers").flat_map do |rule, markers|
          markers.filter_map do |marker|
            at = text.downcase.index(marker)
            build(DiscourseHit.new(rule:, marker:, line: number, from: at, speaker:, text:)) if at
          end
        end
      end

      def build(hit)
        counter = counter_evidence(hit.text)
        hit.observation(counter:, confidence: confidence(counter),
                        alternatives: about("alternatives", hit.rule), limit: about("limit", hit.rule))
      end

      def about(map, rule) = @catalogue.fetch(map).fetch(rule)

      # Wording alone is weak evidence, so the base is low and a quotation or a hedge lowers it.
      def confidence(counter)
        [0.35 - (0.1 * counter.size), 0.1].max.clamp(0.0, Float(@catalogue.fetch("confidence_cap")))
      end

      def counter_evidence(text)
        @catalogue.fetch("counter_markers").select { |marker| text.downcase.include?(marker) }
      end

      def split_speaker(line)
        match = SPEAKER.match(line)
        match ? [match[1], match[2]] : [nil, line]
      end

      def audit(found)
        return unless @audit_path

        FileUtils.mkdir_p(File.dirname(@audit_path))
        File.open(@audit_path, "a") do |file|
          file.puts(JSON.generate(at: Time.now.utc.iso8601, catalogue: version,
                                  observations: found.map { |o| o.to_h.slice(:rule, :line, :from, :to, :confidence) }))
        end
      end
    end
  end
end
