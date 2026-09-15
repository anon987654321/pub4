# frozen_string_literal: true

require "cgi"
require_relative "cdp_session"

module Deploy
  # The journeys a single load cannot see, driven by journey_invariant: following
  # a link into a <turbo-frame>, where focus lands after a Turbo Drive visit, the
  # list a reader without JavaScript pages through, and a conversation log that
  # reconnects under a reader scrolled back through it.
  #
  # Each measure is a script in journey_probe/ and each verdict a method taking
  # the script's answer, so the verdicts are proved on planted answers.
  module TurboJourneys
    PROBES = File.join(__dir__, "journey_probe")
    FRAME = File.read(File.join(PROBES, "turbo_frame.js")).freeze
    FOCUS = File.read(File.join(PROBES, "turbo_focus.js")).freeze
    RECONNECT = File.read(File.join(PROBES, "log_reconnect.js")).freeze

    # Chrome's words for a script whose page went away under it, which is what a
    # click that became a whole-page load looks like from inside the script.
    PAGE_REPLACED = /context was destroyed|inspected target navigated|cannot find context/i
    SENTINEL = /class="infinite-scroll-sentinel"/
    NEXT_LINK = /<a\b(?=[^>]*\brel="next")[^>]*\bhref="([^"]+)"/
    # The tolerance a scroll position gets: two pixels is rounding, not movement.
    DRIFT = 2
    # conversation_log's own idea of "at the newest line".
    TAIL = 80

    module_function

    def measure(cdp, script)
      cdp.evaluate(script, await_promise: true)
    rescue CdpSession::Error => e
      { "error" => e.message }
    end

    def judge_frame(label, answer, result)
      return replaced(label, "frame link", answer, result) if answer["error"]

      Array(answer["lazy"]).select { |frame| frame["missing"] }.each do |frame|
        result.fail("journey_invariant frame: #{label} lazy frame ##{frame["id"]} loaded \"Content missing\" — " \
                    "its src answers without a matching <turbo-frame>")
      end
      return false unless answer["found"]

      frame_outcome(label, answer, result)
      true
    end

    def frame_outcome(label, answer, result)
      where = "#{label} #{answer["href"]} into ##{answer["frame"]}"
      if answer["outcome"] == "missing" || answer["missing"]
        result.fail("journey_invariant frame: #{where} showed \"Content missing\" — " \
                    "the response has no ##{answer["frame"]}")
      elsif !answer["same_document"]
        result.fail("journey_invariant frame: #{where} reloaded the whole page instead of the frame", severity: :soft)
      elsif answer["outcome"] == "timeout"
        result.warn("journey_invariant frame: #{where} did not load within 6s")
      elsif answer["advance"] && !answer["url_changed"]
        result.fail("journey_invariant frame: #{where} declares data-turbo-action=advance and left the URL behind",
                    severity: :soft)
      end
    end

    def judge_focus(label, answer, result)
      return replaced(label, "nav link", answer, result, fault: false) if answer["error"]
      return false unless answer["found"]

      if !answer["same_document"] || answer["outcome"] == "timeout"
        result.warn("journey_invariant focus: #{label} #{answer["href"]} was not a Turbo visit — focus not judged")
      elsif !answer["body"] && !(answer["connected"] && answer["painted"])
        result.fail("journey_invariant focus: #{label} after the Turbo visit to #{answer["href"]} focus sits on " \
                    "#{answer["sel"]}, which is #{answer["connected"] ? "not painted" : "detached"} — " \
                    "the next Tab starts from nowhere a reader can see", severity: :soft)
      end
      true
    end

    def judge_reconnect(label, answer, result)
      unless answer["found"] && answer["scrollable"]
        why = answer["error"] || "has no scrolling conversation log"
        result.warn("journey_invariant reconnect: #{label} #{why} — not measured")
        return false
      end

      reconnect_findings(answer).each do |message|
        result.fail("journey_invariant reconnect: #{label} #{message}", severity: :soft)
      end
      true
    end

    def reconnect_findings(answer)
      findings = []
      moved = answer["reconnected"].to_i - answer["before"].to_i
      pulled = answer["arrived"].to_i - answer["reconnected"].to_i
      findings << "the log's reconnect moved a scrolled-back reader #{moved}px" if moved.abs > DRIFT
      findings << "a new line pulled a scrolled-back reader #{pulled}px" if pulled.abs > DRIFT
      if !answer["pill"]
        findings << "a line arrived below a scrolled-back reader and no jump-to-newest appeared"
      elsif answer["tail_gap"].to_i > TAIL || answer["pill_left"]
        findings << "jump-to-newest left the reader #{answer["tail_gap"]}px above the newest line"
      end
      findings
    end

    # Server HTML only, as a reader without JavaScript receives it. An
    # infinite-scroll sentinel loads the next page from script, so the same HTML
    # has to carry a rel=next link, and that link has to answer.
    def judge_pager(label, html, result, follow:)
      sentinel = html.match?(SENTINEL)
      href = html[NEXT_LINK, 1]
      if sentinel && href.nil?
        result.fail("journey_invariant noscript: #{label} loads further pages only by infinite scroll and carries " \
                    "no rel=next link — without JavaScript the list ends at page one", severity: :soft)
      end
      return false unless href

      status = follow.call(CGI.unescapeHTML(href)).to_i
      unless status.between?(200, 399)
        result.fail("journey_invariant noscript: #{label} rel=next #{href} answers #{status} — " \
                    "the pager's next page is broken")
      end
      true
    end

    # A page replaced under a frame link is the defect; under a nav link it is a
    # full load, which is allowed and leaves nothing to judge.
    def replaced(label, what, answer, result, fault: true)
      if fault && answer["error"].to_s.match?(PAGE_REPLACED)
        result.fail("journey_invariant: #{label} a #{what} replaced the page mid-journey (#{answer["error"]})",
                    severity: :soft)
      else
        result.warn("journey_invariant: #{label} #{what} not measured (#{answer["error"]})")
      end
      false
    end
  end
end
