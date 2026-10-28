# frozen_string_literal: true

# Alias installation — const_set/remove_const at module-open time — is the
# pattern behind the 2026-10-28 boot crash: a head that const_sets into a
# pending zeitwerk autoload crashes the builder chain, and every alias file
# needed 346da8e's remove_const guard to be safe at all. The installation
# sites below are the complete set on record; a new occurrence outside them
# fails this check, and whoever needs one either folds it into the Kernel
# alias files or extends this list knowing what it costs. Retirement of the
# whole set is TODO's execution-contract gate, not this check's job.

require "rbconfig"

root = File.expand_path("..", __dir__)
lib = File.join(root, "lib")

ALIAS_SITES = %w[
  fix/fix_loop/pass_runner/assessment_matrix.rb
  fix/fix_loop/pass_runner.rb
  fix/kernel/convergence_adapter.rb
  fix/kernel/lifecycle.rb
  fix/kernel/repair_adapter.rb
  fix/run_journal.rb
  voice/edge_gec.rb
].freeze

violations = []
Dir.glob(File.join(lib, "**", "*.rb")).sort.each do |path|
  relative = path.delete_prefix("#{lib}/")
  next if ALIAS_SITES.include?(relative)

  File.foreach(path).with_index do |line, index|
    next unless line.match?(/\b(const_set|remove_const)\b/)

    violations << "#{relative}:#{index + 1}: #{line.strip}"
  end
end

if violations.any?
  warn "alias_site_guard: const_set/remove_const outside the recorded alias sites:"
  violations.each { |violation| warn "  #{violation}" }
  warn "alias_site_guard: fold the constant into the Kernel alias files or " \
       "extend ALIAS_SITES in tools/alias_site_guard.rb knowing what it costs"
  exit 1
end

puts "alias_site_guard: #{ALIAS_SITES.size} alias sites on record, none outside them"
