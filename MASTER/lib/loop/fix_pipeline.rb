# frozen_string_literal: true

module Master
  module Loop
  # Architecture #8: staged dataflow pipeline Detect → Triage → Fix → Validate → Apply.
  # Violations flow through named stages as objects. Each stage transforms the packet
  # or returns nil to abort that violation's pipeline run.
  class FixPipeline
    Stage = Struct.new(:name, :handler, keyword_init: true)

    def initialize(agent:, scanner:, bus: nil)
      @agent = agent
      @scanner = scanner
      @bus = bus
      @stages = [
        Stage.new(name: :triage, handler: method(:triage)),
        Stage.new(name: :fix, handler: method(:fix)),
        Stage.new(name: :validate, handler: method(:validate)),
        Stage.new(name: :apply, handler: method(:apply_stage)),
      ]
    end

    # Run violations through all stages. Returns count of applied fixes.
    def run(violations, rule:)
      applied = 0
      violations.each do |v|
        packet = { violation: v, rule: rule, candidate: nil, valid: false }
        result = @stages.reduce(packet) do |pkt, stage|
          break nil if pkt.nil?
          out = stage.handler.call(pkt)
          @bus&.publish("fix_pipeline:stage",
                        stage: stage.name, rule: rule.id,
                        file: pkt[:violation][:file], ok: !out.nil?)
          out
        end
        applied += 1 if result
      end
      applied
    end

    private

    def triage(pkt)
      path = pkt[:violation][:file]
      return nil unless File.exist?(path)
      pkt.merge(src: File.read(path, encoding: "UTF-8"))
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "FixPipeline.triage", event_bus: @bus, path:)
    end

    def fix(pkt)
      response = @agent.ask(fix_prompt(pkt)).to_s
      return nil if response.strip.empty? || response.strip == "UNCHANGED"
      pkt.merge(candidate: response)
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "FixPipeline.fix", event_bus: @bus)
    end

    def validate(pkt)
      candidate = pkt[:candidate]
      return nil unless candidate && candidate.strip != pkt[:src].strip
      pkt.merge(valid: true)
    end

    def apply_stage(pkt)
      return nil unless pkt[:valid]
      path = pkt[:violation][:file]
      temporary_path = "#{path}.pipeline.#{Process.pid}.tmp"
      File.write(temporary_path, pkt[:candidate], encoding: "UTF-8")
      File.rename(temporary_path, path)
      @bus&.publish("fix_pipeline:applied", file: path)
      pkt
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "FixPipeline.apply_stage", event_bus: @bus, path:)
      File.delete(temporary_path) if defined?(temporary_path) && File.exist?(temporary_path) rescue nil
      @bus&.publish("fix_pipeline:write_error", file: path, error: e.message)
      nil
    end

    def fix_prompt(pkt)
      v = pkt[:violation]
      "Fix: #{v[:rule]} — #{v[:message]} at line #{v[:line]} in #{File.basename(v[:file])}.\n" \
        "Return only the corrected file or UNCHANGED.\n\n```\n#{pkt[:src]}\n```"
    end
  end
  end
end
