# frozen_string_literal: true

module Master
  module Builder
    module_function
    def build_scanner(root:, agent:, bus:)
      scanner = Scan::Scanner.new(event_bus: bus)
      [
        Scan::Rules::FrozenStringRule, Scan::Rules::BareRescueRule,
        Scan::Rules::ExplicitRule, Scan::Rules::ImmutableRule,
        Scan::Rules::CqsRule, Scan::Rules::SelfExplainingRule,
        Scan::Rules::LongMethodRule, Scan::Rules::GodClassRule,
        Scan::Rules::DuplicateCodeRule, Scan::Rules::PruneRule,
        Scan::Rules::SrpRule, Scan::Rules::PolaRule,
        Scan::Rules::NielsenRule, Scan::Rules::AxiomCoverageRule
      ].each { |klass| scanner.add_rule(klass.new) }
      scanner.add_rule(Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Scan::Rules::ConceptualRule.new(agent:))
      scanner.add_rule(Scan::Rules::AdversarialRule.new(agent:))
      scanner
    end

    def boot_snapshot(container)
      root = container[:root]
      out = File.join(root, ".master", "snapshot.md")
      dirs = SNAPSHOT_DIRS.map { |d| File.join(root, d) }
      files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                  .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
                  .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                  .sort
      header = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      body = files.flat_map do |f|
        rel = f.sub("#{root}/", "")
        lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        content = File.read(f, encoding: "UTF-8", invalid: :replace)
        ["## #{rel}", "```#{lang}", content.rstrip, "```", ""]
      rescue StandardError
        []
      end
      FileUtils.mkdir_p(File.dirname(out))
      content = (header + body).join("\n")
      File.write(out, content)
      File.write(File.join(root, "snapshot.md"), content)
      container[:bus]&.publish("boot:snapshot", files: files.size)
    rescue StandardError => e
      container[:bus]&.publish("boot:snapshot_error", error: e.message)
    end
  end
end
