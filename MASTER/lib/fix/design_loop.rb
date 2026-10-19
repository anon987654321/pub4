# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "design_edit"
require_relative "layout_score_store"
require_relative "visual_quality_gates"

module Master
  module Fix
    # The loop other agents use for interface work, with MASTER's own measures:
    # look at the weakest surface, ask a vision model for ONE layout edit to a
    # stylesheet, apply it, re-render, and keep the edit only if the surface
    # scored higher and nothing else got worse; otherwise undo it. Each kept edit
    # is its own commit. A surface that stops improving is set aside.
    #
    # Every outside effect is injected (browser, model, CSS build, git) so the
    # loop's decisions are testable without Chrome or a model.
    class DesignLoop
      TIE = 0.05
      OTHERS_TOLERANCE = 1.0
      STALL_LIMIT = 4
      TRIES_PER_SURFACE = 2
      GUARDS = 4
      SOURCE_CHARS = 12_000
      Round = Data.define(:number, :surface, :why, :outcome, :before, :after)

      # What the loop works on and how long.
      Plan = Data.define(:surfaces, :root, :rounds, :candidates)

      # Everything outside: measure ->(surfaces) { [[surface, payload, shot], ...] };
      # ask ->(prompt, image) { reply }; build ->(app) { ok }; commit_file ->(path, message) { ok };
      # sources_for ->(surface) { [stylesheet paths] }; guard ->(path, new_text) { refusal or nil }.
      World = Data.define(:measure, :ask, :build, :commit_file, :sources_for, :guard)

      VARIANTS = [
        "Change as little as possible.",
        "Reach it through a different selector or property than the obvious one.",
        "Prefer an existing token or layout primitive over a new value.",
      ].freeze

      DIRECTION = "Flat, brutalist, Swiss: one sans family, a strict 8px rhythm, tap targets of at least 44px, " \
                  "clear hierarchy, nothing decorative (no gradients, shadows or ornament)."

      def initialize(plan:, world:, say: ->(_) {})
        @plan = plan
        @world = world
        @say = say
        @rejected = []
        @undone = []
        @judged = 0
        @spent = Hash.new(0)
      end

      def run
        @state = measured(@plan.surfaces)
        stalls = 0
        results = []
        @plan.rounds.times do |index|
          break unless (@target = weakest)

          results << attempt(index + 1)
          stalls = results.last.outcome == :kept ? 0 : stalls + 1
          break if stalls >= STALL_LIMIT
        end
        results
      end

      private

      def measured(surfaces)
        @world.measure.call(surfaces).map { |surface, payload, shot| row(surface:, payload:, shot:) }
      end

      def row(surface:, payload:, shot:)
        { surface:, payload:, shot:, score: score(payload), offenders: offenders(surface, payload) }
      end

      def score(payload) = LayoutScoreStore.measure(@plan.root, payload).score

      # {offender name => elements}, only the ones present.
      def offenders(surface, payload)
        found = VisualQualityGates.measure(surface, payload)["offenders"]
        found.transform_values(&:size).reject { |_, count| count.zero? }
      end

      def weakest
        @state.reject { |row| @spent[row[:surface].id] >= TRIES_PER_SURFACE }.min_by { |row| row[:score] }
      end

      def attempt(number)
        return give_up(number) unless refresh

        best = candidates.filter_map { |edit| trial(edit) }.max_by { |tried| tried[:gain] }
        return give_up(number) unless best

        keep(number, best)
      end

      # A fresh baseline for the target and its guards at the start of every round. A
      # score taken minutes ago, or cold, is not comparable with one taken after an edit,
      # and that gap once passed for an improvement.
      def refresh
        @fresh = measured(guards.map { |row| row[:surface] })
        merge(@fresh)
        @target = @fresh.find { |row| row[:surface].id == @target[:surface].id }
        keep_before_shot if @target
        @target
      end

      # Re-rendering overwrites the screenshot, so the picture the vision check
      # compares against is copied aside first.
      def keep_before_shot
        @before_shot = @target[:shot].sub(/\.png\z/, ".before.png")
        FileUtils.cp(@target[:shot], @before_shot)
      end

      def give_up(number)
        @spent[@target[:surface].id] += 1
        round(number:, why: "no usable edit", outcome: :none, after: @target[:score])
      end

      def candidates
        sources = Array(@world.sources_for.call(@target[:surface])).first(4)
        Array.new(@plan.candidates) { |variant| propose(sources, variant) }.compact.uniq(&:key)
      end

      def propose(sources, variant)
        reply = @world.ask.call(prompt(sources, variant), [@target[:shot]])
        edit = DesignEdit.parse(reply, allowed: sources, rules: DesignEdit::Rules.new(guard: @world.guard, scale: nil))
        raise DesignEdit::Refused, "already tried and undone" if @rejected.include?(edit.key)

        edit
      rescue DesignEdit::Refused, StandardError => e
        @say.call("#{@target[:surface].id}: edit not usable, #{e.message.lines.first.to_s.strip}")
        nil
      end

      # Applies the edit, re-renders, judges, and always puts the file back.
      def trial(edit)
        original = edit.apply!
        return nil unless @world.build.call(@target[:surface].app)

        after = measured(@fresh.map { |row| row[:surface] })
        verdict = judge(@fresh, after)
        @say.call("#{@target[:surface].id}: #{edit.why} -> #{verdict[:text]}")
        return { edit:, gain: verdict[:gain], after: } if verdict[:ok]

        @rejected << edit.key
        @undone << "#{edit.why} (#{verdict[:text]})"
        nil
      rescue DesignEdit::Refused => e
        @say.call("#{@target[:surface].id}: edit refused, #{e.message}")
        nil
      ensure
        restore(edit, original) if original
      end

      def restore(edit, original)
        edit.restore(original)
        @world.build.call(@target[:surface].app)
      end

      # The target plus a few others spread across the set: a stylesheet edit is
      # re-measured on a sample, not on every surface, or one round would take hours.
      def guards
        others = @state.reject { |row| row[:surface].id == @target[:surface].id }
        step = [others.size / GUARDS, 1].max
        [@target, *others.each_slice(step).map(&:first).first(GUARDS)]
      end

      def judge(before, after)
        now = after.find { |row| row[:surface].id == @target[:surface].id }
        return { ok: false, text: "not re-rendered" } unless now

        gain = now[:score] - @target[:score]
        notes = problems(before, after)
        better = notes.empty? && (gain >= TIE || (gain >= -TIE && looks_better?(now)))
        { ok: better, gain:, text: summary(now, notes) }
      end

      def summary(now, notes)
        shown = notes + [@vision].compact
        "#{@target[:score].round(1)} -> #{now[:score].round(1)}#{shown.map { |note| ", #{note}" }.join}"
      end

      def problems(before, after)
        notes = []
        others = after.reject { |row| row[:surface].id == @target[:surface].id }
        lower = lower_surfaces(before, others)
        notes << "scored lower: #{lower.join(', ')}" unless lower.empty?
        added = new_offenders(before, after)
        notes << "new gate offenders: #{added.join(', ')}" unless added.empty?
        notes
      end

      def lower_surfaces(before, others)
        others.filter_map do |row|
          was = before.find { |old| old[:surface].id == row[:surface].id }
          drop = (was ? was[:score] : 0) - row[:score]
          "#{row[:surface].id} -#{drop.round(1)}" if drop > OTHERS_TOLERANCE
        end
      end

      # The layout score is geometry arithmetic and does not move for many changes a
      # person would see. When it is flat, a vision model compares the two renders; the
      # order is alternated so the answer does not follow position.
      def looks_better?(now)
        @judged += 1
        order = @judged.odd? ? [@before_shot, now[:shot]] : [now[:shot], @before_shot]
        verdict = JSON.parse(@world.ask.call(vision_prompt, order)[/\{.*\}/m].to_s)
        @vision = "vision: #{verdict['better']}, #{verdict['why']}".strip
        verdict["better"].to_s.upcase == (order.first == now[:shot] ? "A" : "B")
      rescue JSON::ParserError, StandardError
        @vision = "vision: no verdict"
        false
      end

      def vision_prompt
        <<~TEXT
          Two renders of the same page, A then B. Direction: #{DIRECTION}
          Which has the better layout: clearer hierarchy, steadier spacing, nothing cramped or floating?
          Say "same" if you cannot tell them apart.
          Return only JSON: {"better": "A" or "B" or "same", "why": "<one short sentence>"}.
        TEXT
      end

      # "name +n" for each offender kind that grew between two sets of rows.
      def new_offenders(before, after)
        base = tally(before)
        tally(after).filter_map { |name, count| "#{name} +#{count - base[name]}" if count > base[name] }
      end

      def tally(rows)
        rows.each_with_object(Hash.new(0)) { |row, all| row[:offenders].each { |name, count| all[name] += count } }
      end

      def keep(number, best)
        edit = best[:edit]
        edit.apply!
        @world.build.call(@target[:surface].app)
        after = @target[:score] + best[:gain]
        @world.commit_file.call(edit.file, commit_message(edit, after))
        merge(best[:after])
        round(number:, why: edit.why, outcome: :kept, after:)
      end

      def commit_message(edit, after)
        "design: #{edit.why}\n\n" \
          "#{@target[:surface].id} layout score #{@target[:score].round(1)} -> #{after.round(1)}\n" \
          "Made by the operator-run design loop; local until the operator pushes, revert this commit to undo."
      end

      # The rows re-measured after a kept edit replace their old entries; the rest stay.
      def merge(fresh)
        ids = fresh.to_h { |row| [row[:surface].id, row] }
        @state = @state.map { |row| ids.fetch(row[:surface].id, row) }
      end

      def round(number:, why:, outcome:, after:)
        Round.new(number:, surface: @target[:surface].id, why:, outcome:, before: @target[:score], after:)
      end

      def prompt(sources, variant)
        <<~TEXT
          The image is the current render of #{@target[:surface].id}.
          Its layout score is #{@target[:score].round(1)} of 100.
          Weakest measures (0 to 1): #{weakest_measures}.
          Gate offenders: #{@target[:offenders].inspect}.
          Direction: #{DIRECTION}
          Make ONE edit to ONE of the stylesheets below that improves the layout you can see: spacing, alignment,
          sizing, hierarchy, grid or flex structure, overflow, reading width. Change layout properties only, never
          a colour, font, shadow or opacity, never a token file, and keep every spacing value on the declared
          scale or a var(--token).
          #{VARIANTS[variant % VARIANTS.size]}
          #{undone_note}
          Return only JSON: {"file": "<one path below>", "find": "<exact text from that file, occurring once>",
          "replace": "<new text>", "why": "<one short sentence>"}.

          #{sources.map { |path| "FILE #{path}\n#{File.read(path, encoding: 'UTF-8')[0, SOURCE_CHARS]}" }.join("\n\n")}
        TEXT
      end

      def weakest_measures
        subs = LayoutScoreStore.measure(@plan.root, @target[:payload]).subs
        weakest = subs.sort_by { |_, value| value.to_f }.first(3)
        weakest.map { |name, value| "#{name} #{value&.round(2)}" }.join(", ")
      end

      def undone_note
        return "" if @undone.empty?

        "Tried and undone, with the reason: #{@undone.last(4).join(' | ')}. Do something different."
      end
    end
  end
end
