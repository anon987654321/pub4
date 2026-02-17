# frozen_string_literal: true

require "tempfile"
require "yaml"
require "json"
require "erb"

module MASTER
  module SyntaxValidator
    module_function

    def valid?(file:, content:)
      ext = File.extname(file).downcase

      case ext
      when ".rb"
        MASTER::Utils.valid_ruby?(content)
      when ".yml", ".yaml"
        YAML.safe_load(content)
        true
      when ".json"
        JSON.parse(content)
        true
      when ".html", ".htm"
        valid_html?(content)
      when ".erb"
        valid_erb?(content)
      when ".css", ".scss", ".sass"
        valid_css?(content)
      when ".js", ".mjs", ".cjs"
        valid_javascript?(content)
      when ".rs"
        valid_rust?(content)
      else
        true
      end
    rescue StandardError
      false
    end

    def valid_html?(content)
      begin
        require "nokogiri"
      rescue LoadError
        return basic_tag_balance?(content)
      end

      doc = Nokogiri::HTML5(content)
      doc.errors.empty?
    rescue StandardError
      basic_tag_balance?(content)
    end

    def valid_erb?(content)
      ERB.new(content).src
      true
    rescue SyntaxError, StandardError
      false
    end

    def valid_css?(content)
      # Fallback syntax heuristic when no external linter is present.
      return false unless balanced?(content, "{", "}")
      return false unless balanced?(content, "(", ")")
      true
    end

    def valid_javascript?(content)
      return true unless command_available?("node")

      Tempfile.create(["master_js_check", ".js"]) do |f|
        f.write(content)
        f.flush
        system("node", "--check", f.path, out: File::NULL, err: File::NULL)
      end
    end

    def valid_rust?(content)
      return true unless command_available?("rustc")

      Tempfile.create(["master_rs_check", ".rs"]) do |f|
        f.write(content)
        f.flush
        output = "#{f.path}.rmeta"
        system("rustc", "--edition=2021", "--crate-type", "lib", "--emit=metadata",
               "-o", output, f.path, out: File::NULL, err: File::NULL)
      ensure
        File.delete(output) if output && File.exist?(output)
      end
    end

    def command_available?(cmd)
      system("which", cmd, out: File::NULL, err: File::NULL)
    end

    def balanced?(content, open_ch, close_ch)
      count = 0
      content.each_char do |ch|
        count += 1 if ch == open_ch
        count -= 1 if ch == close_ch
        return false if count.negative?
      end
      count.zero?
    end

    def basic_tag_balance?(content)
      opens = content.scan(/<([a-zA-Z][\w:-]*)\b(?![^>]*\/>)[^>]*>/).flatten
      closes = content.scan(%r{</([a-zA-Z][\w:-]*)>}).flatten
      opens.tally == closes.tally
    end
  end
end
