# frozen_string_literal: true

module Deploy
  # A service resource_guard.sh shed and has not brought back yet.
  #
  # The guard sheds amber/bsdports under load and restores them one per tick
  # once pressure clears. It does restore — measured 2026-08-14, both apps were
  # shed at 05:55 and the list cleared itself by 08:55 — but restore is gated on
  # memory recovering past MEM_RESTORE, and on a box whose median availability
  # is 9% that took three hours. For those three hours both apps were down and
  # nothing said so: relayd answers TLS on their behalf, so the outage reads as
  # a hang rather than a 5xx and every other check here passes.
  #
  # That is the gap this closes. Not "the guard is broken" — it is slow enough
  # that the apps are down for hours, which is how
  # OPENBSD/data/debt.yml's "amber_bsdports_stop_and_stay_down" keeps getting
  # reopened by whoever notices amber is off.
  #
  # This asks the observable question — is something the guard shed still not
  # running — rather than reasoning about whether the restore thresholds are
  # reachable. The first version of this check did the latter, and measured
  # against the real 1550-tick history it stayed silent through the very
  # incident it was written for: the gate does open, but rarely, and the log
  # does not record whether anything was shed at the time, so "the gate opened
  # recently" answers a question nobody asked. The shed list plus rcctl answers
  # the one that matters, with no model of the box in between.
  #
  # Status is injected so the rule is decidable off the box. A rule about
  # production that only runs on production is one nobody runs.
  module GuardState
    SHED_STATE = "/var/db/resource_guard_shed"

    module_function

    # nil when healthy, a failure line when the guard's own list names something
    # that is down.
    def shed_and_down(shed:, running:)
      services = shed.to_s.split.reject(&:empty?)
      return nil if services.empty?

      down = services.reject { |svc| running.call(svc) }
      return nil if down.empty?

      "resource guard: #{down.join(', ')} shed and still down — relayd answers TLS for them, so this " \
        "is invisible from outside. `doas rcctl restart #{down.first}` brings one back; if they keep " \
        "landing here, the restore thresholds in OPENBSD/resource_guard.sh no longer reach this box."
    end

    # The guard's list is append-only until its own restore path removes an
    # entry, so a service can sit in it while running perfectly — which means
    # something other than the guard started it, typically a deploy. Stale
    # state, not an outage, and worth telling apart from one: on 2026-08-14 both
    # apps were listed and up for half an hour after a fleet deploy restarted
    # them, before a later guard tick caught up and cleared the list.
    def stale_entries(shed:, running:)
      services = shed.to_s.split.reject(&:empty?)
      services.select { |svc| running.call(svc) }
    end
  end
end
