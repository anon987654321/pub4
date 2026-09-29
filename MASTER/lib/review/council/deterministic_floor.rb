# frozen_string_literal: true

require "open3"
require "rbconfig"
require "yaml"

module Master
  module Review
    module Council
      module DeterministicFloor
        module_function

        TEXT_EXTENSIONS = %w[.rb .rake .gemspec .yml .yaml .json .js .mjs .ts .css .scss .html .erb .md .sh .zsh .ksh .conf .toml].freeze
        SECRET_PATTERNS = {
          "token" => /\b(?:r8|hf|gh[pousr])_[A-Za-z0-9_-]{20,}/,
          "openai-style key" => /\bsk-[A-Za-z0-9_-]{20,}/,
          "private key" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
        }.freeze

        def paths(target)
          path = File.expand_path(target.to_s, Master::ROOT)
          return [path] if File.file?(path)
          return Dir.glob(File.join(path, "**", "*")).select { |item| File.file?(item) }.sort if File.directory?(path)

          raise ArgumentError, "checklist-floor: target does not exist: #{target}"
        end

        def run(target)
          files = paths(target).select { |path| TEXT_EXTENSIONS.include?(File.extname(path).downcase) }
          raise "checklist-floor: no supported text files under #{target}" if files.empty?

          failures = []
          notices = []
          files.each do |path|
            rel = path.delete_prefix("#{Master::ROOT}/")
            body = File.binread(path)
            failures << "#{rel}: invalid UTF-8" unless body.dup.force_encoding(Encoding::UTF_8).valid_encoding?
            SECRET_PATTERNS.each { |name, regex| failures << "#{rel}: possible #{name}" if body.match?(regex) }

            case File.extname(path).downcase
            when ".rb", ".rake", ".gemspec"
              output, status = Open3.capture2e(RbConfig.ruby, "-c", path)
              failures << "#{rel}: Ruby syntax — #{output.lines.last.to_s.strip}" unless status.success?
            when ".yml", ".yaml", ".json"
              begin
                YAML.safe_load(body, aliases: false)
              rescue Psych::Exception => e
                failures << "#{rel}: YAML/JSON parse — #{e.message.lines.first.to_s.strip}"
              end
            when ".sh", ".zsh", ".ksh"
              shell = body.lines.first.to_s.include?("zsh") ? "zsh" : "sh"
              output, status = Open3.capture2e(shell, "-n", path)
              failures << "#{rel}: #{shell} syntax — #{output.lines.last.to_s.strip}" unless status.success?
            end

            body.each_line.with_index(1) do |line, number|
              next if line.lstrip.start_with?("#", "<%#")

              notices << "#{rel}:#{number}: TODO/FIXME" if line.match?(/\b(?:TODO|FIXME)\b/)
            end
          end

          files.each { |path| puts "floor0: checked=#{path.delete_prefix("#{Master::ROOT}/")}" }
          notices.first(20).each { |line| puts "floor0: note #{line}" }
          warn "floor0: #{failures.join("\n")}" unless failures.empty?
          puts "floor0: #{files.length} file(s), #{notices.length} note(s), #{failures.length} failure(s)"
          failures.empty? ? 0 : 1
        end
      end
    end
  end
end
