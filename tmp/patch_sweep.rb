# Phase 1: Sweep corruption guard patch
path = "/home/dev/pub4/MASTER/lib/master/sweep.rb"
src = File.read(path)

# 1. Add ERROR_PATTERNS constant after SEVERITY_RANK
src.sub!(
  "SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze",
  <<~'RUBY'.chomp
SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze

    ERROR_PATTERNS = /
      \b(?:error|exception|traceback|failed|cannot|unable\sto|
      undefined\smethod|no\smethod|syntax\serror|
      internal\sserver|rate\slimit|quota\sexceeded|
      apologize|as\san\sai|i\scannot|i\sam\sunable)\b
    /ix.freeze
  RUBY
)

# 2. Add YAML and ERB syntax checkers
src.sub!(
  '".sh" => ->(p) { system("bash -n #{p}  > /dev/null 2>&1") }',
  <<~'RUBY'.chomp
".sh"  => ->(p) { system("bash -n #{p}  > /dev/null 2>&1") },
      ".yml" => ->(p) { begin; YAML.safe_load_file(p); true; rescue => _e; false; end },
      ".erb" => ->(p) { begin; ERB.new(File.read(p)).result(binding); true; rescue SyntaxError; false; rescue => _e; true; end }
  RUBY
)

# 3. Replace @agent.ask with @agent.ask_result + Result check + length guard
old_rewrite = <<~'RUBY'
    def rewrite(path, rel)
      src  = File.read(path, encoding: "UTF-8")
      ext  = File.extname(path)
      lang = { ".rb" => "ruby", ".sh" => "sh", ".yml" => "yaml",
               ".md" => "markdown", ".erb" => "erb" }.fetch(ext, "text")

      response = @agent.ask(build_prompt(src, rel, lang))
      extract(response.to_s, lang)
    rescue StandardError => e
      @bus&.publish("sweep:rewrite_error", file: path, error: e.message)
      nil
    end
RUBY

new_rewrite = <<~'RUBY'
    def rewrite(path, rel)
      src  = File.read(path, encoding: "UTF-8")
      ext  = File.extname(path)
      lang = { ".rb" => "ruby", ".sh" => "sh", ".yml" => "yaml",
               ".md" => "markdown", ".erb" => "erb" }.fetch(ext, "text")

      result = @agent.ask_result(build_prompt(src, rel, lang))
      unless result.respond_to?(:ok?) && result.ok?
        @bus&.publish("sweep:rewrite_error", file: path, error: "LLM returned error")
        return nil
      end

      new_src = extract(result.value!.to_s, lang)
      return nil unless new_src

      # 50% minimum length guard — reject if output is less than half the original
      if new_src.bytesize < (src.bytesize * 0.5)
        @bus&.publish("sweep:length_rejected", file: rel, original: src.bytesize, new: new_src.bytesize)
        return nil
      end

      new_src
    rescue StandardError => e
      @bus&.publish("sweep:rewrite_error", file: path, error: e.message)
      nil
    end
RUBY

src.sub!(old_rewrite, new_rewrite)

# 4. Add error pattern rejection in extract()
old_extract = '    def extract(text, lang)
      return nil if text.strip == "UNCHANGED"

      fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?\n(.*?)```/m
      return text.match(fence_re)[1]         if text.match?(fence_re)
      return text.match(/```\n(.*?)```/m)[1] if text.match?(/```\n(.*?)```/m)

      text.strip.empty? ? nil : text
    end'

new_extract = '    def extract(text, lang)
      return nil if text.strip == "UNCHANGED"

      # Reject short responses that look like error messages
      if text.bytesize < 500 && ERROR_PATTERNS.match?(text)
        return nil
      end

      fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?\n(.*?)```/m
      return text.match(fence_re)[1]         if text.match?(fence_re)
      return text.match(/```\n(.*?)```/m)[1] if text.match?(/```\n(.*?)```/m)

      text.strip.empty? ? nil : text
    end'

src.sub!(old_extract, new_extract)

File.write(path, src)
puts "Sweep patched successfully"
puts `ruby -c #{path} 2>&1`
