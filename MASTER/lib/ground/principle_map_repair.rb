# frozen_string_literal: true

require "fileutils"
require "set"

module Master
  module Ground
    # bin/doctor --fix's config self-repair (OpenClaw's doctor --fix
    # pattern): known, safe-to-automate drift in principle_map.yml.
    #
    # In scope: rule_ids pointing at a RuleDSL id that no longer exists
    # (renamed rule, deleted rule, typo). Found and fixed by hand twice
    # this session before this existed -- a dangling reference is a
    # broken pointer, not real content, so removing it can't lose
    # information the way blindly deduping an ambiguous duplicate key
    # could. That class stays report-only (see Map::Principle#integrity),
    # not auto-fixed, for the same reason OpenClaw's doctor --fix
    # explains before rewriting rather than guessing.
    module PrincipleMapRepair
      # Rule.registry is empty until something references
      # Master::Review::Scan::RuleDSL (Zeitwerk-autoload trigger -- a bare
      # `require "master"` alone leaves it at 0). Confirmed by hand while
      # building this: without the trigger in #dangling_rule_ids, every
      # rule_id in the file looks "dangling" against an empty registry
      # and this would delete all of them. MIN_REGISTRY_SIZE is a second,
      # independent guard in case the trigger itself ever silently stops
      # working -- refuse to treat a suspiciously small registry as
      # ground truth for what to delete.
      MIN_REGISTRY_SIZE = 100

      module_function

      # Returns [[principle_id, rule_id], ...] for every dangling
      # reference, without modifying anything.
      def dangling_rule_ids(root:)
        Master::Review::Scan::RuleDSL
        registry = Master::Review::Scan::Rule.registry
        return [] if registry.size < MIN_REGISTRY_SIZE

        registered = registry.filter_map { |klass| Master::Review::Scan::RuleFactory.registry_id(klass, root:)&.upcase }.to_set
        # law/ is the second rule population: a rule whose registry twin
        # retired lives on there, and its principle-map reference is a live
        # pointer, not a dangling one. Loaded from Master::ROOT because law/
        # is global like the registry — `root:` here may be a fixture dir.
        registered |= law_rule_ids
        map = Master::Ground::Map::Principle.load(root:)
        map.principles.each_with_object([]) do |(id, entry), acc|
          entry.rule_ids.each { |rid| acc << [id, rid] unless registered.include?(rid.to_s.upcase) }
        end
      end

      # Backs up principle_map.yml (.bak) and removes each dangling
      # reference's line in place. Returns the same [[principle_id,
      # rule_id], ...] list that was removed (empty if nothing to do, or
      # if the registry looked too small to trust -- see
      # MIN_REGISTRY_SIZE).
      def fix!(root:)
        path = File.join(root, "data", "principle_map.yml")
        return [] unless File.file?(path)

        dangling = dangling_rule_ids(root:)
        return [] if dangling.empty?

        FileUtils.cp(path, "#{path}.bak")
        text = File.read(path)
        dangling.each { |principle_id, rule_id| text = remove_rule_id_line(text, principle_id, rule_id) }
        File.write(path, text)
        dangling
      end

      def law_rule_ids
        require File.join(Master::ROOT, "law", "law")
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?
        ::Law.rules.keys.map { |id| id.to_s.upcase }.to_set
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PrincipleMapRepair.law_rule_ids", severity: :load_bearing)
        Set.new
      end

      def remove_rule_id_line(text, principle_id, rule_id)
        lines = text.lines
        start_index = lines.find_index { |l| l.match?(/\A  #{Regexp.escape(principle_id)}:\s*\n\z/) }
        return text unless start_index

        end_index = lines[(start_index + 1)..].find_index { |l| l.match?(/\A  \S/) }
        block_end = end_index ? start_index + 1 + end_index : lines.size
        target = lines[start_index...block_end].find_index { |l| l.match?(/\A    - #{Regexp.escape(rule_id)}\s*\n\z/) }
        return text unless target

        lines.delete_at(start_index + target)
        lines.join
      end
    end
  end
end
