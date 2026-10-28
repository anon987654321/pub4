# frozen_string_literal: true

require_relative "transaction"
require_relative "write_guard"

module Master
  module Fix
    # The tap-target repair RAILS writes by hand (_site_legal.scss, _minimal.scss): padding grows
    # a control's own box to --tap-min and an equal negative margin hands the space back, so
    # nothing around it moves. Kept only when the re-render hook agrees.
    module TapTargetPad
      LAWS = /touch|tap|target_spacing|fitts/i
      INLINE_TAG = /\A(?:a|span)(?=[.#])/
      REASON = "reaches --tap-min: padding grows its own box, an equal negative margin hands the space back."

      module_function

      def applicable?(group) = group.law.to_s.match?(LAWS) && !group.selector.to_s.empty?

      def rule(selector)
        lines = ["/* #{selector} #{REASON} */", "#{selector} {"]

        # Block padding on an inline box paints but does not grow the box a finger is measured against.
        lines << "  display: inline-block;" if selector.match?(INLINE_TAG)
        lines << "  min-inline-size: var(--tap-min);"
        lines << "  padding-block: max(0px, (var(--tap-min) - 1lh) / 2);"
        lines << "  margin-block: min(0px, (1lh - var(--tap-min)) / 2);"
        lines << "}"
        lines.join("\n") + "\n"
      end

      # The stylesheets that already style the selector's last class or id, so the pad
      # lands beside the rules it adjusts. A sheet that vanished mid-run styles nothing.
      def stylesheets_for(selector, stylesheets)
        token = selector.to_s[/[.#][A-Za-z_][\w-]+\z/] or return []
        pattern = /#{Regexp.escape(token)}(?![\w-])/
        Array(stylesheets).select { |path| File.file?(path) && File.read(path, encoding: "UTF-8").match?(pattern) }
      end

      # :applied, :already_padded, :guard_refused, :score_dropped, :finalize_failed or :no_rescore. Without a
      # re-render hook nothing is written: an unmeasured layout edit is a guess.
      def apply(path, selector, root:, rescore:)
        return :no_rescore unless rescore

        old = File.read(path, encoding: "UTF-8")
        return :already_padded if old.include?("#{selector} {") && old.include?("var(--tap-min)")

        updated = "#{old.chomp}\n\n#{rule(selector)}"
        return :guard_refused if WriteGuard.default.verdict(path:, content: updated).blocked?

        transaction = Transaction.new(root:, paths: [path]).begin!
        begin
          File.write(path, updated)
          transaction.observe!
          kept = rescore.call(path)
        rescue StandardError
          transaction.rollback!
          raise
        end
        # finalize! answers a Result either way; an err one is not a kept pad.
        return(transaction.finalize!.ok? ? :applied : :finalize_failed) if kept

        transaction.rollback!
        :score_dropped
      end
    end
  end
end
