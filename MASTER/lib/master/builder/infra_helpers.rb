# frozen_string_literal: true

module Master
  module Builder
    module_function

    def build_scanner(root:, agent:, bus:)
      scanner = Scan::Scanner.new(event_bus: bus)
      Scan::Rule.registry.select(&:auto_build?).each { |klass| scanner.add_rule(klass.new) }
      scanner.add_rule(Scan::Rules::AxiomCoverageRule.new(root:))
      scanner.add_rule(Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Scan::Rules::InterconnectRule.new(root:))
      scanner.add_rule(Scan::Rules::SemanticRule.new(agent:))
      scanner.add_rule(Scan::Rules::AdversarialRule.new(agent:))
      scanner.add_rule(Scan::Rules::CommentDriftRule.new(agent:))
      scanner.add_rule(Scan::Rules::SemanticOpportunityRule.new(agent:))
      scanner
    end

    def boot_snapshot(container)
      root  = container[:root]
      files = collect_snapshot_files(root)
      body  = render_snapshot_body(root, files)
      write_snapshot(root, files, body)
      container[:bus]&.publish("boot:snapshot", files: files.size)
    rescue StandardError => e
      container[:bus]&.publish("boot:snapshot_error", error: e.message)
    end

    def collect_snapshot_files(root)
      SNAPSHOT_DIRS.flat_map { |d| Dir.glob(File.join(root, d, "**", "*")) }
                   .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
                   .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                   .sort
    end

    def render_snapshot_body(root, files)
      files.flat_map do |f|
        rel  = f.sub("#{root}/", "")
        lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        src  = File.read(f, encoding: "UTF-8", invalid: :replace)
        ["## #{rel}", "```#{lang}", src.rstrip, "```", ""]
      rescue StandardError => _e
        []
      end
    end

    def write_snapshot(root, files, body)
      header  = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      content = (header + body).join("\n")
      out     = File.join(root, ".master", "snapshot.md")
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, content)
      File.write(File.join(root, "snapshot.md"), content)
    end
  end
end
