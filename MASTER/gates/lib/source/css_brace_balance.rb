# frozen_string_literal: true

require_relative "../../support/fleet"
require_relative "../../support/gate_result"
require_relative "../../../tools/scss"

module Deploy
  # A stylesheet with one unclosed brace nests every rule behind it in the
  # browser and silently kills them — seen ship on face.css, whose #primer stub
  # at :1434 held every rule under EOF (chat-log's 66ch centering among them)
  # while every gate read green. Nothing in the repo parsed CSS for structure:
  # the tests assert by substring, and the one lexing instrument here,
  # ScssRules, is a rule extractor, not a validator — an unmatched `}` pops a
  # nil frame there and is a silent no-op.
  #
  # This gate counts block braces over the lexer's structure stream, which
  # excludes braces inside strings, comments and interpolation, so the count
  # says what the browser sees. It fails on an unclosed block and on an extra
  # close, naming file and line. Hand-authored sources only — build output has
  # no place a balance could be repaired in.
  class CssBraceBalanceGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    APPS = Fleet.app_names.freeze
    MASTER_WEB = %w[RAILS/master_web/public/face.css RAILS/master_web/public/chat_upload.css].freeze

    def self.run = new.run

    def run
      result = GateResult.new
      files = css_files
      return result.inconclusive!("css_brace_balance: no stylesheets found") if files.empty?

      files.each { |path| check(result, path) }
      result.checked!(files.count)
      result
    end

    private

    def check(result, path)
      structure, = Operator::ScssRules.lex(File.read(path))
      opens = []
      extra = nil
      line = 1
      structure.each do |char|
        line += 1 if char == "\n"
        next unless char == "{" || char == "}"

        if char == "{"
          opens << line
        elsif opens.empty? && extra.nil?
          extra = line
        else
          opens.pop
        end
      end
      if opens.first
        result.fail("css_brace_balance: #{relative(path)} block opened on line #{opens.first} never closes — " \
                    "every rule behind it is nested inside it and stops matching")
      elsif extra
        result.fail("css_brace_balance: #{relative(path)} line #{extra} closes a block that was never opened — " \
                    "every rule before it read as nested")
      end
    end

    # Same corpus shape CssConstitutionGate scans: every app and engine
    # stylesheet, minus build output, plus RAILS/master_web's two named source files.
    def css_files
      rails = APPS.flat_map do |app|
        bases = [File.join(RAILS, app, "app/assets/stylesheets")]
        bases.concat(Dir.glob(File.join(RAILS, app, "engines/*/app/assets/stylesheets")))
        bases.flat_map do |base|
          next [] unless File.directory?(base)

          Dir.glob(File.join(base, "**/*.{scss,css}")).reject do |p|
            p.include?("/vendor/") || p.include?("/node_modules/") || p.include?("/builds/") ||
              p.match?(/\.map\z/)
          end
        end
      end

      (rails + master_web_files).uniq
    end

    def master_web_files
      MASTER_WEB.map { |rel| File.join(ROOT, rel) }.select { |p| File.file?(p) }
    end

    def relative(path)
      path.sub("#{ROOT}/", "")
    end
  end
end
