# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Master
  module Fix
    # What /fix has learned from the model, so it stops asking what it already
    # asked. Opus declined about a third of the findings it was sent, and every
    # run sent the same unchanged files again: a decline is kept against the
    # file's content, and asked again only once the file changes. A rule the
    # model declines nearly every time is mostly reporting false findings, so
    # past RETIRE_AFTER asks at RETIRE_RATIO it is no longer sent at all, and the
    # run says which rule and why, so the rule is fixed instead.
    class RepairMemory
      PATH = File.join(".master", "fix_memory.json")
      RETIRE_AFTER = 20
      RETIRE_RATIO = 0.8
      DECLINED = %i[no_proposal].freeze
      APPLIED = %i[applied commit_refused].freeze
      LOCK = Mutex.new
      ANNOUNCED = Set.new
      # A rule's detector fingerprint, once per process: the code a process
      # runs does not change under it (a reload is a new process).
      DETECTORS = {}

      def initialize(root:)
        @root = root
        @file = File.join(root, PATH)
      end

      # The findings still worth a model call: not declined for the file as it
      # is now, and not of a retired rule.
      def fresh(path, findings)
        data = load
        declined = declined_for(path, data)
        findings.reject { |finding| declined.include?(finding[:rule].to_s) || retired?(finding[:rule], data) }
      end

      def retired?(rule_id, data = load)
        stats = data.dig("rules", rule_id.to_s)
        return false unless stats && stats["asked"].to_i >= RETIRE_AFTER

        return false if (stats["declined"].to_f / stats["asked"]) < RETIRE_RATIO

        # Once per rule: the counts still move while in-flight repairs land, so
        # the line itself cannot be the key.
        ANNOUNCED.add?(rule_id.to_s) && Master::Trace::Dmesg.status(
          "fix0", "#{rule_id} retired from model repair: declined #{stats["declined"]} of #{stats["asked"]}"
        )
        true
      end

      # What the model said about a rule describes the detector that found the
      # findings. Once the detector's source changes (a false positive fixed),
      # its count starts afresh and the file declines it earned go with it;
      # otherwise a fixed rule stays retired on the old detector's record. The
      # fingerprint is the detector's whole source file, so an edit beside it
      # also resets, which costs only a few asks. A count kept before
      # fingerprints existed adopts the current one.
      def sync_detectors(rules)
        marks = rules.to_h { |rule| [rule.id.to_s, DETECTORS.fetch(rule.id.to_s) { DETECTORS[rule.id.to_s] = detector_digest(rule) }] }
        LOCK.synchronize do
          data = load
          changed = marks.count { |id, digest| digest && refingerprint(data, id, digest) }
          save(data) if changed.positive?
        end
      end

      # outcomes is a repair's breakdown, { outcome_symbol => count }. A call the
      # model never answered (quota, no lane) says nothing about the findings,
      # so it counts as neither an ask nor a decline.
      def record(path, rule_ids, outcomes)
        verdict = verdict_for(outcomes)
        return if verdict == :unanswered

        LOCK.synchronize do
          data = load
          rule_ids.each { |id| tally(data, id.to_s, verdict) }
          remember_file(data, path, rule_ids, verdict)
          save(data)
        end
      end

      private

      # True when the stats changed: a first fingerprint, or a new detector.
      def refingerprint(data, id, digest)
        stats = data["rules"][id]
        return false if stats.nil? || stats["detector"] == digest

        unless stats["detector"].nil?
          data["rules"][id] = { "asked" => 0, "declined" => 0, "applied" => 0 }
          data["files"].each_value { |entry| entry["declined"] = Array(entry["declined"]) - [id] }
          ANNOUNCED.delete(id)
          Master::Trace::Dmesg.status("fix0", "#{id} detector changed; its repair record starts afresh")
        end
        data["rules"][id]["detector"] = digest
        true
      end

      def detector_digest(rule)
        klass = rule.class
        block = klass.respond_to?(:dsl_block) ? klass.dsl_block : nil
        source = block&.source_location || klass.instance_method(:check).source_location
        file = source&.first
        file && File.file?(file) ? Digest::SHA256.file(file).hexdigest[0, 16] : nil
      rescue NameError
        nil
      end

      def verdict_for(outcomes)
        keys = Array(outcomes&.keys).map(&:to_sym)
        return :applied if keys.intersect?(APPLIED)
        return :unanswered if keys.include?(:model_failed)

        keys.intersect?(DECLINED) ? :declined : :other
      end

      def tally(data, id, verdict)
        stats = (data["rules"][id] ||= { "asked" => 0, "declined" => 0, "applied" => 0 })
        stats["asked"] += 1
        stats["declined"] += 1 if verdict == :declined
        stats["applied"] += 1 if verdict == :applied
      end

      # A decline is kept against the content it was about; a repair changes the
      # file, so what was declined before no longer describes it.
      def remember_file(data, path, rule_ids, verdict)
        key = relative(path)
        return data["files"].delete(key) if verdict == :applied
        return unless verdict == :declined

        entry = data["files"][key]
        sha = digest(path)
        earlier = entry && entry["sha"] == sha ? Array(entry["declined"]) : []
        data["files"][key] = { "sha" => sha, "declined" => (earlier + rule_ids.map(&:to_s)).uniq }
      end

      def declined_for(path, data)
        entry = data.dig("files", relative(path))
        entry && entry["sha"] == digest(path) ? Array(entry["declined"]) : []
      end

      def load
        return { "files" => {}, "rules" => {} } unless File.file?(@file)

        { "files" => {}, "rules" => {} }.merge(JSON.parse(File.read(@file)))
      rescue JSON::ParserError
        { "files" => {}, "rules" => {} }
      end

      def save(data)
        FileUtils.mkdir_p(File.dirname(@file))
        File.write(@file, JSON.pretty_generate(data) + "\n")
      end

      def digest(path) = File.file?(path) ? Digest::SHA256.file(path).hexdigest : ""
      def relative(path) = File.expand_path(path).delete_prefix("#{File.expand_path(@root)}/")
    end
  end
end
