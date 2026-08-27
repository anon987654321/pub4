# frozen_string_literal: true

require_relative "baseline_ratchet"

module Pub4
  # A destructive control that asks nothing before it fires.
  #
  # The third of the uninstrumented rows in OPENBSD/data/debt.yml's
  # rails_audit_backlog — "29 destructive links with no confirmation
  # interstitial" — a hand count with no committed tool behind it.
  #
  # unconfirmed_destroy — a link or button that issues DELETE and carries no
  # confirmation. Rails routes destruction through the method, not the label, so
  # this reads the method: it matches `method: :delete`, `turbo_method: :delete`
  # and `data-turbo-method="delete"`, and is satisfied by `confirm:`,
  # `turbo_confirm:` or `data-turbo-confirm`. A control with a name like
  # "Delete account" and a GET is not this finding; a control labelled "Leave"
  # that issues DELETE is.
  #
  # Two reasons a control legitimately skips the prompt: the action is reversible
  # (unfollow, unsave, leave a room you can rejoin), or the click already
  # happened inside a dialog that asked. Mark those with
  # `<%# destructive: no-confirm-ok — <reason> %>` on the line above; the marker
  # takes a reason because "reversible" is a claim about the model, not the view.
  #
  # button_to is included. It renders a form and is the correct way to do this,
  # but a form that submits DELETE without asking is the same event for the
  # person clicking it.
  module DestructiveActionLint
    RAILS_ROOT = File.expand_path("../../..", __dir__)

    VIEW_GLOBS = [
      "{amber,brgen,bsdports,shared}/app/views/**/*.erb",
      "brgen/engines/*/app/views/**/*.erb"
    ].freeze

    DESTRUCTIVE = /method:\s*:delete|turbo_method:\s*:delete|data-turbo-method=["']delete["']/
    CONFIRMED = /confirm:|data-turbo-confirm|turbo_confirm/
    OPT_OUT = "destructive: no-confirm-ok"

    # Measured 2026-08-25 at first run: 30, against the register's hand count of
    # 29 from a fortnight earlier. Reproducing a number counted by eye is the
    # reason to trust the detector, so it is recorded rather than driven to zero.
    #
    # Most of the 30 are reversible and want the marker rather than a prompt —
    # sign out, unfollow, unpin, leave a community you can rejoin, remove a plan
    # entry. A handful are moderation actions where a prompt is the right answer.
    # That split is per-site judgement, which is what the register said all along;
    # what it lacked was a number that could not drift while nobody looked.
    BASELINES = { "unconfirmed_destroy" => 30 }.freeze

    Finding = Struct.new(:kind, :file, :line, :detail)

    extend Pub4::BaselineRatchet

    module_function

    def view_files
      VIEW_GLOBS.flat_map { |glob| Dir.glob(File.join(RAILS_ROOT, glob)) }.uniq.sort
    end

    def scan
      view_files.flat_map { |path| findings_for(path, File.read(path, encoding: "UTF-8").scrub) }
    end

    # A call can wrap over several lines, so the unit is the ERB tag rather than
    # the line — matching per line reported a confirmed control as unconfirmed
    # whenever the confirm: sat on the next one.
    def findings_for(path, src)
      rel = path.sub("#{RAILS_ROOT}/", "")
      offset = 0
      src.scan(/<%.*?%>|<a\b[^>]*>|<button\b[^>]*>/m).filter_map do |tag|
        offset = src.index(tag, offset) || offset
        line = src[0, offset].count("\n") + 1
        offset += tag.length
        next unless tag.match?(DESTRUCTIVE)
        next if tag.match?(CONFIRMED)
        next if opted_out?(src, line)

        Finding.new("unconfirmed_destroy", rel, line, tag.gsub(/\s+/, " ")[0, 70])
      end
    end

    # The marker sits on its own line above the call, where a reader meets it
    # before the code it excuses.
    def opted_out?(src, line)
      window = src.lines[[line - 4, 0].max...line].to_a.join
      window.include?(OPT_OUT)
    end

    def run
      findings = scan
      tally = counts(findings)
      over = tally.select { |kind, count| count > BASELINES.fetch(kind) }

      over.each_key { |kind| warn "destructive_action_lint: #{kind} #{tally[kind]} exceeds baseline #{BASELINES.fetch(kind)}" }
      tally.each { |kind, count| puts "destructive_action_lint: #{kind} #{count} (baseline #{BASELINES.fetch(kind)})" }
      findings.first(20).each { |f| puts "  #{f.file}:#{f.line} #{f.detail}" }
      over.empty?
    end
  end
end

exit(Pub4::DestructiveActionLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
