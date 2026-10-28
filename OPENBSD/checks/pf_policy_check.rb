# frozen_string_literal: true

require_relative "../../MASTER/checks/support/check_result"

module Deploy
  # Checks the tracked PF ruleset's narrow, documented safety invariants.
  #
  # This is deliberately not a complete pf.conf parser. PF has macros, tables,
  # anchors, translation rules and stateful rule semantics; pretending a few
  # regular expressions understand all of that would produce dangerous
  # confidence. These checks cover only invariants which are explicit in the
  # repository's current policy and leave full syntax validation to pfctl -nf.
  class PfPolicyCheck
    ROOT = File.expand_path("../..", __dir__)
    CONFIG = File.join("OPENBSD", "etc", "pf.conf")
    Rule = Struct.new(:line, :action, :text, keyword_init: true)

    def self.run(root: ROOT)
      new(root:).run
    end

    def initialize(root: ROOT)
      @root = File.expand_path(root)
    end

    def run
      result = CheckResult.new
      path = File.join(@root, CONFIG)
      unless File.file?(path)
        result.fail("pf_policy: tracked OPENBSD/etc/pf.conf is missing")
        return result
      end

      source = File.read(path, encoding: "UTF-8")
      rules = parse_rules(source)
      result.checked!

      block_index = rules.index { |rule| default_deny?(rule) }
      if block_index.nil?
        result.fail("pf_policy: default-deny 'block log all' (or 'block all') is missing")
      else
        first_pass = rules.index { |rule| rule.action == "pass" }
        if first_pass && block_index > first_pass
          result.fail("pf_policy: default-deny block appears after the first pass rule")
        end
      end

      broad_passes = rules.select { |rule| unscoped_pass?(rule) }
      broad_passes.each do |rule|
        result.fail("pf_policy: line #{rule.line} contains unscoped #{rule.text.inspect}")
      end

      inbound = rules.select { |rule| rule.action == "pass" && rule.text.match?(/\Apass\s+in\b/) }
      inbound.each do |rule|
        next if rule.text.match?(/\bon\s+\$ext_if\b/)

        result.fail("pf_policy: inbound pass on line #{rule.line} is not scoped to $ext_if")
      end

      check_bruteforce_order(rules, result)
      result
    rescue SystemCallError, EncodingError => e
      result ||= CheckResult.new
      result.fail("pf_policy: cannot inspect tracked ruleset: #{e.class}: #{e.message}")
      result
    end

    private

    # Preserve source line numbers while joining PF's backslash-continued rules.
    # Only pass/block/match statements are analyzed; other PF grammar is left to
    # pfctl's native parser rather than approximated here.
    def parse_rules(source)
      rules = []
      pending = nil
      pending_line = nil

      source.each_line.with_index(1) do |line, number|
        clean = line.sub(/\s+#.*\z/, "").rstrip
        next if clean.strip.empty?

        if clean.end_with?("\\")
          pending_line ||= number
          fragment = clean.delete_suffix("\\").strip
          pending = [pending, fragment].compact.reject(&:empty?).join(" ")
          next
        end

        logical = [pending, clean.strip].compact.reject(&:empty?).join(" ")
        start_line = pending_line || number
        pending = nil
        pending_line = nil
        next unless logical.match?(/\A(?:pass|block|match)\b/)

        rules << Rule.new(line: start_line, action: logical.split(/\s+/, 2).first, text: logical)
      end

      rules
    end

    def default_deny?(rule)
      rule.action == "block" && rule.text.match?(/\Ablock(?:\s+log)?\s+all(?:\s|\z)/)
    end

    # A pass rule must identify the managed external interface. The one
    # intentional exception is the current ICMP-type allowlist, retained from
    # the tracked policy; broad protocol passes must not slip past the check
    # merely because they do not end with the words "pass all".
    GLOBAL_ICMP_ALLOW = /\Apass\s+inet\s+proto\s+icmp\s+all\s+icmp-type\s+\{\s*echoreq,\s*unreach,\s*timex\s*\}\z/.freeze

    def unscoped_pass?(rule)
      return false unless rule.action == "pass"
      return false if rule.text.match?(/\bon\s+\$ext_if\b/)
      return false if rule.text.match?(GLOBAL_ICMP_ALLOW)

      true
    end

    def check_bruteforce_order(rules, result)
      brute_index = rules.index do |rule|
        rule.action == "block" && rule.text.match?(/\Ablock\s+quick\s+from\s+<bruteforce>(?:\s|\z)/)
      end
      ssh_index = rules.index do |rule|
        rule.action == "pass" &&
          rule.text.match?(/\Apass\s+in\s+quick\s+on\s+\$ext_if\b/) &&
          rule.text.match?(/\bport\s+22\b/)
      end

      unless brute_index
        result.fail("pf_policy: quick block for <bruteforce> is missing")
        return
      end

      unless ssh_index
        result.fail("pf_policy: explicit quick SSH exception on $ext_if port 22 is missing")
        return
      end

      if ssh_index > brute_index
        result.fail("pf_policy: explicit SSH exception must precede the <bruteforce> quick block")
      end

      rules.each_with_index do |rule, index|
        next unless rule.action == "pass" && rule.text.match?(/\Apass\s+in\b/)
        next if index == ssh_index || index > brute_index

        result.fail("pf_policy: inbound pass on line #{rule.line} precedes the <bruteforce> quick block")
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  result = Deploy::PfPolicyCheck.run
  unless result.ok?
    warn result.failures.join("\n")
    exit 1
  end
  puts "pf-policy: tracked ruleset invariants passed"
end
