# frozen_string_literal: true

require "yaml"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # An app's own translation, overridden by the shared engine, silently.
  #
  # `shared/` is mounted by every app, and its locale files are merged with the
  # app's. When both define a key, one value renders and the other is dead — and
  # nothing anywhere says which. The failure is invisible by construction: the
  # string is present in the app's own nb.yml, in the app's own repo, and the
  # page shows something else.
  #
  # Which one wins was measured rather than reasoned about, by booting bsdports
  # and reading I18n.load_path for a key defined in both:
  #
  #   idx 15  shared/config/locales/social.nb.yml   "Hopp til hovedinnhold"
  #   idx 17  bsdports/config/locales/nb.yml        "Hopp til innholdet"
  #   idx 24  shared/config/locales/social.nb.yml   "Hopp til hovedinnhold"
  #
  # The shared engine's locale path is in load_path TWICE, and the second
  # registration lands after every app's own locales. Last write wins, so shared
  # always does. The first reasoning attempt — engines load before the app,
  # therefore the app wins — was correct about Rails and wrong about this tree,
  # and would have shipped a gate that named the wrong file as dead.
  #
  # The visible cost today is nav.brand_home: brgen sets "Brgen home", amber sets
  # "Amber home", shared sets "Home", and all three render "Home".
  #
  # Keys where both files agree are not reported. They are redundant rather than
  # wrong, there are ~180 of them, and a gate whose output is mostly harmless
  # duplication is one people learn to skip.
  class LocaleShadowingGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    APPS = %w[amber brgen bsdports].freeze
    BUDGET = File.join(__dir__, "../../data/locale_shadowing.yml")

    # runner.rb calls the class, not an instance — `klass.run` at runner.rb:132.
    # Getting this wrong does not fail loudly: the gate registers, appears in
    # --list, and reports "ERRORED and blocked nothing", which is a green-ish
    # line for a gate that never ran.
    def self.run
      new.run
    end

    def initialize(result = GateResult.new)
      @result = result
    end

    def run
      shared = load_locales(File.join(RAILS_ROOT, "shared/config/locales/**/*.yml"))
      if shared.empty?
        @result.inconclusive!("locale_shadowing: no shared locale files found at shared/config/locales")
        return @result
      end

      budgets = read_budget
      APPS.each do |app|
        judge(app, shared, budgets)
        @result.checked!
      end
      judge_orphans
      @result
    end

    private

    # A key with no value deletes whatever a later merge would have kept.
    #
    # Removing the last child of a YAML mapping leaves the parent behind as a
    # bare `nav:`, which parses as nil — and in I18n's deep merge nil REPLACES a
    # Hash rather than being ignored. shared/ loads after every app, so one such
    # key there wiped all 48 nav entries in brgen, 23 in amber and 8 in bsdports.
    # Every navigation label in every app, from deleting one line.
    #
    # The shadowing check above could not see it: it compares values that
    # disagree, and a key resolving to nothing disagrees with nobody. So it stayed
    # green while three apps rendered "Translation missing" everywhere.
    #
    # Only shared/ can do this damage, because only shared/ loads last. An empty
    # key in an app's own file is a dead declaration rather than a weapon, so it
    # warns there and fails here.
    def judge_orphans
      %w[shared amber brgen bsdports].each do |tree|
        Dir[File.join(RAILS_ROOT, tree, "config/locales/**/*.yml")].sort.each do |path|
          doc = begin
            YAML.safe_load_file(path, aliases: true)
          rescue StandardError
            next
          end
          next unless doc.is_a?(Hash)

          empties = []
          doc.each do |locale, tree_body|
            next unless tree_body.is_a?(Hash)

            collect_empty(tree_body, [locale.to_s], empties)
          end
          next if empties.empty?

          rel = path.sub("#{RAILS_ROOT}/", "")
          message = "locale_shadowing #{rel}: #{empties.length} key(s) with no value " \
                    "(#{empties.first(4).join(', ')}) — a bare key parses as nil and nil " \
                    "REPLACES a hash in I18n's merge"
          tree == "shared" ? @result.fail(message) : @result.warn(message)
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
      own = load_locales(File.join(RAILS_ROOT, app, "config/locales/**/*.yml"))
      return @result.inconclusive!("locale_shadowing #{app}: no locale files") if own.empty?

      shadowed = own.keys.select { |key| shared.key?(key) && own[key] != shared[key] }
      ceiling = budgets[app]

      if ceiling.nil?
        @result.warn("locale_shadowing #{app}: #{shadowed.size} shadowed with no ceiling in locale_shadowing.yml")
        return
      end

      if shadowed.size > ceiling
        examples = shadowed.sort.first(3)
                           .map { |key| "#{key} (app #{own[key].inspect} is dead, shared #{shared[key].inspect} renders)" }
        @result.fail("locale_shadowing #{app}: #{shadowed.size} shadowed key(s) exceeds ceiling #{ceiling} " \
                     "(+#{shadowed.size - ceiling}). #{examples.join('; ')} — " \
                     "delete the app's copy, or change the shared one")
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
        rescue StandardError
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
      return {} unless File.file?(BUDGET)

      YAML.safe_load_file(BUDGET).to_h { |k, v| [k.to_s, Integer(v)] }
    rescue StandardError => e
      # An empty budget is every ceiling at zero, which reads as a gate that
      # found nothing rather than one that could not read its own limits.
      warn "locale_shadowing: #{File.basename(BUDGET)} unreadable (#{e.class}: #{e.message.lines.first.to_s.strip}) — no budgets applied"
      {}
    end

    def record_low(app, count)
      budgets = read_budget.merge(app => count)
      File.write(BUDGET, budgets.sort.to_h.to_yaml)
    end
  end
end
