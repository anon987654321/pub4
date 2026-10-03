# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "exemplar_structure"
require_relative "visual_quality"
require_relative "dom_surface_schema"

module Deploy
  # Compare human labels to gate scores; measure agreement; suggest weight tweaks.
  class GateCalibration
    ROOT = File.expand_path("..", __dir__) # RAILS/gates
    DATA = File.join(ROOT, "data", "calibration.yml")
    WEIGHTS_OUT = File.join(ROOT, "data", "calibration_weights.yml")

    CaseResult = Struct.new(
      :id, :human, :gate, :agree, :detail, :notes, keyword_init: true
    )

    def self.load(path = DATA)
      YAML.safe_load_file(path)
    end

    def initialize(config: nil, gates_root: ROOT)
      @config = config || self.class.load
      @gates_root = gates_root
      @floor = @config["agreement_floor"].to_f
      @floor = 0.85 if @floor <= 0
      @soft_band = @config["soft_band"].to_i
      @soft_band = 15 if @soft_band <= 0
      @exemplars = ExemplarStructure.new
      @quality = VisualQuality.new(config: quality_config)
      @schema = DomSurfaceSchema.new
    end

    def run
      cases = Array(@config["labels"]).map { |row| evaluate(row) }
      agreed = cases.count(&:agree)
      total = cases.size
      rate = total.positive? ? (agreed.to_f / total) : 0.0
      {
        cases: cases,
        agreed: agreed,
        total: total,
        agreement: rate.round(4),
        floor: @floor,
        pass: rate + 1e-9 >= @floor,
        suggestions: suggest_weights(cases),
        false_positives: cases.select { |c| !c.agree && c.human == "pass" && c.gate == "fail" },
        false_negatives: cases.select { |c| !c.agree && c.human == "fail" && c.gate == "pass" },
      }
    end

    # Write calibration_weights.yml from tune: section + suggestions merge.
    def apply_weights!(report = nil)
      report ||= run
      tune = @config["tune"] || {}
      weights = (tune["quality_weights"] || {}).dup
      report[:suggestions].each do |s|
        next unless s[:dimension] && weights.key?(s[:dimension].to_s)

        weights[s[:dimension].to_s] = s[:suggested]
      end
      payload = {
        "schema" => 1,
        "generated_by" => "GateCalibration",
        "agreement" => report[:agreement],
        "quality_weights" => weights,
        "quality_target" => tune["quality_target"] || 80,
        "layout_search_target" => tune["layout_search_target"] || 90,
        "notes" => report[:suggestions].map { |s| s[:message] },
      }
      File.write(WEIGHTS_OUT, YAML.dump(payload))
      WEIGHTS_OUT
    end

    private

    def quality_config
      base = VisualQuality.load
      # Overlay committed calibration weights if present
      if File.file?(WEIGHTS_OUT)
        cal = YAML.safe_load_file(WEIGHTS_OUT)
        if cal["quality_weights"].is_a?(Hash)
          base["weights"] = base["weights"].merge(cal["quality_weights"])
        end
        base["target_score"] = cal["quality_target"] if cal["quality_target"]
      end
      # Seed tune weights as starting point when no applied file
      tune = @config.dig("tune", "quality_weights")
      if tune.is_a?(Hash) && !File.file?(WEIGHTS_OUT)
        base["weights"] = base["weights"].merge(tune)
      end
      base
    end

    def evaluate(row)
      id = row["id"]
      human = row["human"].to_s
      html = read_fixture(row["fixture"])
      detail = {}
      gate_verdict = "pass"
      notes = []

      if row["exemplar"]
        r = @exemplars.score(html, row["exemplar"])
        detail[:exemplar_score] = r.score
        detail[:exemplar_max] = r.max
        detail[:exemplar_target] = r.target
        detail[:exemplar_missing] = r.missing_required
        unless r.pass?
          gate_verdict = r.missing_required.any? ? "fail" : "soft"
          notes.concat(r.notes)
        end
      end

      if row["quality"]
        q = @quality.score(html, surface: (row["surface"] || "generic").to_sym)
        detail[:quality_score] = q.score
        detail[:quality_max] = q.max
        detail[:quality_target] = q.target
        detail[:quality_notes] = q.notes
        unless q.pass?
          # soft if close to target
          gate_verdict =
            if q.score + @soft_band >= q.target
              gate_verdict == "fail" ? "fail" : "soft"
            else
              "fail"
            end
          notes.concat(q.notes)
        end
      end

      # Surface schema if id maps to a schema name
      schema_id = row["schema"] || infer_schema(row)
      if schema_id && schema_exists?(schema_id)
        findings = @schema.check(html, schema_id)
        hard = findings.select { |f| f.severity == :hard }
        soft = findings.select { |f| f.severity == :soft }
        detail[:schema_hard] = hard.size
        detail[:schema_soft] = soft.size
        if hard.any?
          gate_verdict = "fail"
          notes << "schema_hard=#{hard.size}"
        elsif soft.any? && gate_verdict == "pass"
          gate_verdict = "soft"
        end
      end

      agree = agreement?(human, gate_verdict, detail)
      CaseResult.new(
        id: id,
        human: human,
        gate: gate_verdict,
        agree: agree,
        detail: detail,
        notes: notes
      )
    end

    def agreement?(human, gate, detail)
      case human
      when "pass"
        gate == "pass" || gate == "soft"
      when "fail"
        gate == "fail"
      when "soft"
        true # soft labels accept any non-crash verdict; prefer not hard-fail only
      else
        false
      end
    end

    def suggest_weights(cases)
      suggestions = []
      fps = cases.select { |c| c.human == "pass" && c.gate == "fail" }
      fns = cases.select { |c| c.human == "fail" && c.gate == "pass" }

      # Count quality note tags on false positives
      note_counts = Hash.new(0)
      fps.each do |c|
        Array(c.detail[:quality_notes]).each do |n|
          dim = n.to_s.split(":").first
          note_counts[dim] += 1
        end
      end
      weights = (@config.dig("tune", "quality_weights") || VisualQuality.load["weights"])
      note_counts.each do |dim, count|
        next unless weights.key?(dim)
        next if count < 1

        current = weights[dim].to_i
        suggested = [current - 3, 5].max
        suggestions << {
          dimension: dim,
          current: current,
          suggested: suggested,
          message: "False positives mention #{dim} ×#{count} — consider weight #{current}→#{suggested}",
        }
      end

      if fns.any?
        target = (@config.dig("tune", "quality_target") || 80).to_i
        suggestions << {
          dimension: "quality_target",
          current: target,
          suggested: [target + 5, 95].min,
          message: "False negatives ×#{fns.size} — consider raising quality_target #{target}→#{[target + 5, 95].min} or stronger exemplars",
        }
      end

      if fps.any? && note_counts.empty?
        suggestions << {
          dimension: nil,
          message: "False positives ×#{fps.size}: #{fps.map(&:id).join(', ')} — review exemplar required parts",
        }
      end

      suggestions
    end

    def read_fixture(rel)
      path = File.join(@gates_root, rel)
      raise "missing calibration fixture #{rel}" unless File.file?(path)

      File.read(path)
    end

    def infer_schema(row)
      fix = row["fixture"].to_s
      return Regexp.last_match(1) if fix =~ %r{fixtures/surfaces/(?:good|bad)_(.+)\.html\z}

      nil
    end

    def schema_exists?(id)
      DomSurfaceSchema.load_all.key?(id.to_s)
    end
  end
end
