# frozen_string_literal: true

require "yaml"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # An app overriding a shared translation, counted so each override is chosen.
  #
  # `shared/` is mounted by every app, and its locale files are merged with the
  # app's. When both define a key, one value renders and the other is dead in
  # that app, and nothing on the page says which.
  #
  # Which one wins is measured, by booting bsdports and reading I18n.load_path:
  #
  #   10-15  shared/config/locales/{affiliate,legal,social}.{en,nb}.yml
  #   16-17  bsdports/config/locales/{en,nb}.yml
  #
  # shared loads once, ahead of the app, and the last write wins, so the app's
  # value renders: nb a11y.skip_to_content reads bsdports' "Hopp til innholdet",
  # not shared's "Hopp til hovedinnhold". The shadowed count is therefore the set
  # of the app's deliberate overrides, and the ceiling holds it so a new one is
  # a decision rather than a copy that drifted.
  #
  # Keys where both files agree are not reported. They are redundant rather than
  # wrong, and a gate whose output is mostly harmless duplication is one people
  # learn to skip.
  class LocaleShadowingGate
    ROOT = File.expand_path("../../../..", __dir__)
    APPS = %w[amber brgen bsdports].freeze
    BUDGET = File.join(__dir__, "../../data/locale_shadowing.yml")

    # runner.rb calls the class, not an instance — `klass.run` at runner.rb:132.
    # Getting this wrong does not fail loudly: the gate registers, appears in
    # --list, and reports "ERRORED and blocked nothing", which is a green-ish
    # line for a gate that never ran.
    def self.run(root: ROOT, apps: APPS, budget: BUDGET)
      new(root:, apps:, budget:).run
    end

    def initialize(result = GateResult.new, root: ROOT, apps: APPS, budget: BUDGET)
      @result = result
      @rails_root = File.join(root, "RAILS")
      @apps = apps
      @budget = budget
    end

    def run
      shared = load_locales(File.join(@rails_root, "shared/config/locales/**/*.yml"))
      if shared.empty?
        @result.inconclusive!("locale_shadowing: no shared locale files found at shared/config/locales")
        return @result
      end

      budgets = read_budget
      @apps.each { |app| judge(app, shared, budgets) }
      judge_orphans
      @result
    end

    private

    # A key with no value deletes whatever an earlier merge put under it.
    #
    # Removing the last child of a YAML mapping leaves the parent behind as a
    # bare `nav:`, which parses as nil, and in I18n's deep merge nil REPLACES a
    # Hash rather than being ignored. One such key in shared once wiped every
    # nav label in all three apps.
    #
    # The shadowing check cannot see it: it compares values that disagree, and a
    # key resolving to nothing disagrees with nobody. Every tree fails on it. An
    # app loads after shared, so an app's bare key wipes shared's subtree in that
    # app; shared's own files load in sorted order, so a bare key in social wipes
    # the same subtree from affiliate and legal.
    def judge_orphans
      %w[shared amber brgen bsdports].each do |tree|
        Dir[File.join(@rails_root, tree, "config/locales/**/*.yml")].sort.each do |path|
          doc = begin
            YAML.safe_load_file(path, aliases: true)
          rescue StandardError => e
            @result.inconclusive!("locale_shadowing #{path}: locale file unreadable (#{e.class}: #{e.message})")
            next
          end
          next unless doc.is_a?(Hash)

          empties = []
          doc.each do |locale, tree_body|
            next unless tree_body.is_a?(Hash)

            collect_empty(tree_body, [locale.to_s], empties)
          end
          next if empties.empty?

          rel = path.sub("#{@rails_root}/", "")
          message = "locale_shadowing #{rel}: #{empties.length} key(s) with no value " \
                    "(#{empties.first(4).join(', ')}) — a bare key parses as nil and nil " \
                    "REPLACES a hash in I18n's merge"
          @result.fail(message)
        end
      end
    end

    def collect_empty(node, prefix, out)
      node.each do |key, value|
        path = prefix + [key.to_s]
        if value.is_a?(Hash)
          value.empty? ? out << path.join(".") : collect_empty(value, path, out)
        elsif value.nil?
          out << path.join(".")
        end
      end
    end

    def judge(app, shared, budgets)
      own = load_locales(File.join(@rails_root, app, "config/locales/**/*.yml"))
      return @result.inconclusive!("locale_shadowing #{app}: no locale files") if own.empty?
      # A count taken with a locale file unread is not a count, so the app is
      # not counted as checked; load_locales has already named the file.
      return if @unreadable

      shadowed = own.keys.select { |key| shared.key?(key) && own[key] != shared[key] }
      ceiling = budgets[app]

      # Without a ceiling there is nothing to hold the count against, so this
      # app is reported and not counted as checked. A missing budget therefore
      # leaves the gate inconclusive rather than passed.
      if ceiling.nil?
        @result.warn("locale_shadowing #{app}: #{shadowed.size} shadowed with no ceiling in locale_shadowing.yml")
        return
      end

      @result.checked!

      if shadowed.size > ceiling
        examples = shadowed.sort.first(3)
                           .map { |key| "#{key} (app #{own[key].inspect} renders, shared #{shared[key].inspect} is dead here)" }
        @result.fail("locale_shadowing #{app}: #{shadowed.size} app override(s) of shared keys exceeds ceiling #{ceiling} " \
                     "(+#{shadowed.size - ceiling}). #{examples.join('; ')} — " \
                     "delete the app's copy to take shared's, or raise the ceiling for an override the app means")
      elsif shadowed.size < ceiling
        @result.warn("locale_shadowing #{app}: #{shadowed.size}, under its #{ceiling} ceiling " \
                     "(-#{ceiling - shadowed.size}) — GATE_LOCALE_RATCHET=1 records the new low")
        record_low(app, shadowed.size) if GateResult.flag?("GATE_LOCALE_RATCHET")
      end
    end

    # Flattened to "locale.a.b.c" so two files that nest differently still
    # collide on the key that I18n actually resolves.
    def load_locales(glob)
      Dir[glob].sort.each_with_object({}) do |path, acc|
        doc = begin
          YAML.safe_load_file(path, aliases: true)
        rescue StandardError => e
          @unreadable = true
          @result.inconclusive!("locale_shadowing: locale file unreadable #{path} (#{e.class}: #{e.message})")
          next
        end
        next unless doc.is_a?(Hash)

        doc.each do |locale, tree|
          next unless tree.is_a?(Hash)

          flatten(tree, [locale.to_s], acc)
        end
      end
    end

    def flatten(node, prefix, out)
      node.each do |key, value|
        if value.is_a?(Hash)
          flatten(value, prefix + [key.to_s], out)
        else
          out[(prefix + [key.to_s]).join(".")] = value
        end
      end
      out
    end

    def read_budget
      unless File.file?(@budget)
        @result.inconclusive!("locale_shadowing: budget missing at #{@budget} — shadowing ceilings were not measured")
        return {}
      end

      YAML.safe_load_file(@budget).to_h { |k, v| [k.to_s, Integer(v)] }
    rescue StandardError => e
      # No budget means no ceiling. Keep the per-app loop useful for diagnostics,
      # but make the gate outcome explicitly incomplete rather than clean.
      @result.inconclusive!("locale_shadowing: budget unreadable (#{e.class}: #{e.message}) — shadowing ceilings were not measured")
      {}
    end

    def record_low(app, count)
      budgets = read_budget.merge(app => count)
      File.write(@budget, budgets.sort.to_h.to_yaml)
    end
  end
end
