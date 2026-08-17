# frozen_string_literal: true

# law/ — the constitution as code.
#
# A law exists only as a triple: detector + a fixture it MUST flag + a fixture
# it MUST NOT flag. A law with no detector is documentation. A law with no bad
# fixture is unfalsifiable. A law with no good fixture has an unmeasured
# false-positive rate — the decorator-massacre failure mode. All three or it
# does not load. `rake dogfood` proves every law against its own fixtures and
# then runs every law over law/ itself; both must stay clean.
#
# Contract: `rake dogfood` is the archaeological audit. A capability that goes
# missing is a fixture that stops passing — nothing to compare by hand.
module Law
  Finding = Data.define(:id, :file, :line, :text)

  MEMBERS = %i[id source severity languages scope path absent detect fix bad good].freeze
  Rule = Data.define(*MEMBERS) do
    def applies?(file, language)
      return false if path && !file.include?(path)
      language.nil? || languages.empty? || languages.include?(language)
    end

    def scan(text, file: "-")
      scope == :file ? scan_file(text, file) : scan_lines(text, file)
    end

    # A rule proves itself before it may judge anything else.
    def prove!
      raise ArgumentError, "#{id}: bad fixture not flagged" if scan(bad).empty?
      raise ArgumentError, "#{id}: good fixture flagged" unless scan(good).empty?
      self
    end

    private

    def scan_file(text, file)
      return [] if absent && text.match?(absent)
      return [] unless detect.call(text)
      [Finding.new(id, file, 1, text[/.*/])]
    end

    def scan_lines(text, file)
      text.each_line.with_index(1).filter_map do |line, n|
        Finding.new(id, file, n, line.chomp) if detect.call(line)
      end
    end
  end

  class Builder
    %i[source severity languages scope path absent fix bad good].each { |a| define_method(a) { |v| @h[a] = v } }

    def initialize(id) = @h = { id: id, severity: :warn, languages: [], scope: :line, path: nil, absent: nil }
    def detect(&block) = @h[:detect] = block

    def build
      missing = %i[detect bad good].reject { |k| @h.key?(k) }
      raise ArgumentError, "#{@h[:id]}: missing #{missing.join(', ')}" unless missing.empty?
      Rule.new(**@h.slice(*MEMBERS)).prove!
    end
  end

  @rules = {}
  class << self
    attr_reader :rules

    def define(id, &block)
      b = Builder.new(id)
      b.instance_eval(&block)
      raise ArgumentError, "duplicate law #{id}" if @rules.key?(id)
      @rules[id] = b.build
    end

    def load_all(dir = __dir__)
      Dir.glob(File.join(dir, "*.rb")).sort.each { |f| require f unless f == __FILE__ }
      @rules
    end

    def scan(file, language: nil)
      text = File.read(file, encoding: "UTF-8")
      text = conduct(text) if file.start_with?(__dir__)
      @rules.values.select { |r| r.applies?(file, language) }.flat_map { |r| r.scan(text, file: file) }
    end

    # A law file necessarily contains the pattern it forbids: in its detector,
    # its fix text, and its bad fixture. Those lines declare evidence; they are
    # not conduct. Neutralize them (keeping line numbers) before a law judges law/.
    def conduct(text)
      fence = nil
      text.each_line.map do |line|
        if fence
          fence = nil if line.strip == fence
          next "#\n"
        end
        fence = line[/^\s*(?:bad|good)\s+<<~(\w+)/, 1]
        line.match?(/^\s*(?:source|detect|fix|bad|good)\b/) ? "#\n" : line
      end.join
    end
  end
end
