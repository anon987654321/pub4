# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require_relative "../../MASTER/gates/support/cdp_session"
require_relative "../../MASTER/gates/support/mobile_journey_probe"

# The mobile journey probe is two halves: JavaScript that decides what a phone
# user can safely do on a page, and Ruby that does it and records what changed.
# The JavaScript runs here under node against a small DOM with a real selector
# matcher, and the Ruby runs against a CDP double, so both are exercised rather
# than read.
class TestMobileJourneyStateMachine < Minitest::Test
  Surface = Struct.new(:id, :url, :viewport, keyword_init: true)

  # Enough DOM for the probe's scripts: elements with attributes, a form
  # relation, focus, and querySelectorAll over the selector forms the probe
  # uses (tag, #id, [attr], [attr='v'], ^=, *=, the i flag, :not(), descendant and
  # child combinators matched on their last compound). Every call an element
  # receives is logged, so a test can see a click or a form submit happen.
  FAKE_DOM = <<~'JS'
    const spec = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const base = new URL(spec.url);
    const els = [];
    const byId = (id) => els.find((e) => e.id === id);
    const lastCompound = (sel) => {
      let depth = 0, start = 0;
      for (let i = 0; i < sel.length; i++) {
        const c = sel[i];
        if (c === "[" || c === "(") depth++;
        else if (c === "]" || c === ")") depth--;
        else if (depth === 0 && (c === " " || c === ">")) start = i + 1;
      }
      return sel.slice(start).trim();
    };
    const attrMatch = (e, cond) => {
      const m = cond.match(/^\[([\w-]+)(?:([\^*]?=)['"]?([^'"\]]*?)['"]?(\s+i)?)?\]$/);
      if (!m) throw new Error("fake DOM cannot match " + cond);
      const val = e.getAttribute(m[1]);
      if (!m[2]) return val !== null;
      if (val === null) return false;
      const fold = (s) => (m[4] ? s.toLowerCase() : s);
      const have = fold(val), want = fold(m[3]);
      if (m[2] === "=") return have === want;
      if (m[2] === "^=") return have.startsWith(want);
      return have.includes(want);
    };
    const compoundMatch = (e, compound) => {
      let rest = compound;
      const tag = rest.match(/^[a-z]+/);
      if (tag) {
        if (e.tagName.toLowerCase() !== tag[0]) return false;
        rest = rest.slice(tag[0].length);
      }
      while (rest.length) {
        let m;
        if ((m = rest.match(/^:not\(([^)]*)\)/))) {
          if (compoundMatch(e, m[1])) return false;
        } else if ((m = rest.match(/^#([\w-]+)/))) {
          if (e.id !== m[1]) return false;
        } else if ((m = rest.match(/^\[[^\]]*\]/))) {
          if (!attrMatch(e, m[0])) return false;
        } else if ((m = rest.match(/^:popover-open/))) {
          if (!e.popoverOpen) return false;
        } else {
          throw new Error("fake DOM cannot match " + rest);
        }
        rest = rest.slice(m[0].length);
      }
      return true;
    };
    const matches = (e, sel) => sel.split(",").some((part) => compoundMatch(e, lastCompound(part.trim())));
    const make = (o) => {
      const e = {
        id: o.id || "", tagName: o.tag.toUpperCase(), nodeType: 1, textContent: o.text || "",
        disabled: !!o.disabled, open: !!o.open, popoverOpen: !!o.popover_open,
        attrs: Object.assign(o.id ? { id: o.id } : {}, o.attrs || {}), log: [],
        parentElement: null, previousElementSibling: null, labels: [],
      };
      e.getAttribute = (n) => (n in e.attrs ? String(e.attrs[n]) : null);
      e.hasAttribute = (n) => n in e.attrs;
      e.getBoundingClientRect = () => (o.hidden ? { width: 0, height: 0 } : { width: 40, height: 20 });
      e.matches = (s) => matches(e, s);
      e.closest = (s) => (matches(e, s) ? e : e.form && matches(e.form, s) ? e.form : null);
      e.focus = () => { e.log.push("focus"); document.activeElement = e; };
      e.click = () => e.log.push("click");
      e.submit = () => e.log.push("submit");
      e.reportValidity = () => { e.log.push("reportValidity"); return !!o.valid; };
      e.dispatchEvent = (event) => e.log.push(event.type);
      e.querySelector = (s) => els.find((x) => x.form === e && matches(x, s)) || null;
      if (o.tag === "a" && o.attrs && o.attrs.href) e.href = new URL(o.attrs.href, base).href;
      if (o.tag === "select") {
        e.options = (o.options || []).map((value) => ({ value, disabled: false }));
        e.value = e.options.length ? e.options[0].value : "";
      }
      return e;
    };
    (spec.elements || []).forEach((o) => els.push(make(o)));
    (spec.elements || []).forEach((o, i) => { if (o.form) els[i].form = byId(o.form); });
    globalThis.location = base;
    globalThis.CSS = { escape: (s) => s };
    globalThis.getComputedStyle = (e) => ({
      display: e.getBoundingClientRect().width ? "block" : "none", visibility: "visible", pointerEvents: "auto",
    });
    globalThis.document = {
      body: { innerText: spec.body || "" },
      activeElement: null,
      querySelectorAll: (s) => els.filter((e) => matches(e, s)),
      querySelector: (s) => els.find((e) => matches(e, s)) || null,
    };
    document.activeElement = byId(spec.active) || document.body;
    const result = (0, eval)(spec.script);
    process.stdout.write(JSON.stringify({ result, log: Object.fromEntries(els.map((e) => [e.id, e.log])) }));
  JS

  URL = "https://brgen.test/feed"

  def page(elements, script, active: nil, body: "")
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)
    out, err, status = Open3.capture3("node", "-e", FAKE_DOM,
                                      stdin_data: JSON.generate(url: URL, elements:, script:, active:, body:))
    assert status.success?, err
    JSON.parse(out)
  end

  def discover(elements) = JSON.parse(page(elements, Deploy::MobileJourneyProbe::ACTION_DISCOVERY)["result"])

  def act(elements, kind, selector)
    script = format(Deploy::MobileJourneyProbe::ACTION, selector: selector.to_json, kind: kind.to_json)
    run = page(elements, script)
    [JSON.parse(run["result"]), run["log"]]
  end

  # Navigation the probe may follow is a same-origin GET that changes the page
  # and deletes nothing. Every unsafe link is listed ahead of the two safe ones,
  # so the MAX_NAVIGATIONS cap cannot be what keeps them out.
  NAVIGATION = [
    { id: "self", tag: "a", attrs: { href: "/feed" }, text: "Feed" },
    { id: "ext", tag: "a", attrs: { href: "https://elsewhere.test/events" }, text: "Events" },
    { id: "mail", tag: "a", attrs: { href: "mailto:post@brgen.no" }, text: "Mail" },
    { id: "logout", tag: "a", attrs: { href: "/session/logout" }, text: "Leave" },
    { id: "drop", tag: "a", attrs: { href: "/posts/1" }, text: "Delete post" },
    { id: "method", tag: "a", attrs: { href: "/posts/2", "data-method" => "delete" }, text: "Archive" },
    { id: "turbo", tag: "a", attrs: { href: "/posts/3", "data-turbo-method" => "post" }, text: "Pin" },
    { id: "hidden", tag: "a", attrs: { href: "/secret" }, text: "Secret", hidden: true },
    { id: "events", tag: "a", attrs: { href: "/events" }, text: "Events" },
    { id: "people", tag: "a", attrs: { href: "/people?page=2" }, text: "People" },
  ].freeze

  def test_discovers_only_safe_same_origin_get_navigation
    navigation = discover(NAVIGATION).select { |action| action["kind"] == "navigation" }

    assert_equal %w[#events #people], navigation.map { |action| action["selector"] }
    assert_equal "https://brgen.test/events", navigation.first["href"]
  end

  def test_discovers_search_and_filter_states
    actions = discover([
      { id: "q", tag: "input", attrs: { type: "search" } },
      { id: "post-form", tag: "form", attrs: { method: "post" } },
      { id: "remember", tag: "input", attrs: { type: "checkbox" }, form: "post-form" },
      { id: "get-form", tag: "form" },
      { id: "sort", tag: "select", form: "get-form", options: %w[new old] },
      { id: "kind", tag: "select", form: "get-form", options: %w[all mine] },
    ])

    assert_equal ["#q"], actions.select { |a| a["kind"] == "search" }.map { |a| a["selector"] }
    # A control in a POST form would change data; the first GET control is the one filter.
    assert_equal ["#sort"], actions.select { |a| a["kind"] == "filter" }.map { |a| a["selector"] }
  end

  def test_validation_and_filter_actions_never_submit_a_form
    elements = [
      { id: "signup", tag: "form", attrs: { method: "post" } },
      { id: "email", tag: "input", attrs: { required: "" }, form: "signup" },
      { id: "get-form", tag: "form" },
      { id: "sort", tag: "select", form: "get-form", options: %w[new old] },
    ]

    result, log = act(elements, "validation", "#email")
    assert_equal({ "ok" => true, "state" => "invalid", "active" => true }, result)
    assert_includes log["email"], "reportValidity"

    result, log = act(elements, "filter", "#sort")
    assert_equal "filter_changed", result["state"]
    assert_equal %w[focus input change], log["sort"]

    refute_includes log.values.flatten, "submit"
  end

  def test_state_signature_covers_non_text_state
    elements = [
      { id: "menu", tag: "button", attrs: { "aria-expanded" => "true" } },
      { id: "sheet", tag: "div", attrs: { popover: "" }, popover_open: true },
      { id: "faq", tag: "details", attrs: { open: "" } },
      { id: "confirm", tag: "dialog", open: false },
      { id: "q", tag: "input", attrs: { type: "search" } },
    ]
    cdp = Object.new
    runner = self
    cdp.define_singleton_method(:evaluate) { |js| runner.page(elements, js, active: "q", body: "Feed")["result"] }

    state = Deploy::MobileJourneyProbe.state_signature(cdp)

    assert_equal [%w[menu true]], state["expanded"]
    assert_equal [["sheet", true], ["faq", true], ["confirm", false]], state["open"]
    assert_equal "q", state["active"]
  end

  # A CDP double that keeps a history stack, so back and forward move the URL
  # the probe's state signature reads.
  class HistoryCdp
    attr_reader :calls

    def initialize(url, action)
      @history = [url]
      @index = 0
      @action = action
      @calls = []
    end

    def url = @history[@index]

    def navigate(target)
      @calls << [:navigate, target]
      @history = @history.first(@index + 1) << target
      @index += 1
    end

    def back = (@calls << [:back]) && @index -= 1
    def forward = (@calls << [:forward]) && @index += 1
    def screenshot(path, **) = @calls << [:screenshot, path]

    def evaluate(js)
      return JSON.generate([@action]) if js == Deploy::MobileJourneyProbe::ACTION_DISCOVERY
      return "complete" if js == "document.readyState"
      return JSON.generate(url:, active: "", text: "", expanded: [], open: []) if js.include?("location.href")

      navigate(@action["href"]) # the ACTION script clicked the link
      JSON.generate(ok: true, state: "navigation_started", href: @action["href"])
    end
  end

  def test_navigation_records_the_return_path_through_real_history
    surface = Surface.new(id: "brgen/feed/mobile", url: URL, viewport: "mobile")
    action = { "kind" => "navigation", "selector" => "#events", "label" => "Events", "href" => "https://brgen.test/events" }
    cdp = HistoryCdp.new("about:blank", action)

    rows = Deploy::MobileJourneyProbe.run(cdp, surface, Dir.tmpdir)

    assert_equal %w[navigation navigation_back navigation_forward], rows.map { |row| row["kind"] }
    back = rows[1]
    assert_equal ["https://brgen.test/events", URL], back.values_at("from", "to")
    assert back["changed"] == false, "going back must land on the page the journey started from"
    assert_equal [URL, "https://brgen.test/events"], rows[2].values_at("from", "to")
    assert_equal %i[back forward], cdp.calls.map(&:first) & %i[back forward]
  end

  def test_desktop_surfaces_are_not_walked
    surface = Surface.new(id: "brgen/feed/desktop", url: URL, viewport: "desktop")

    assert_empty Deploy::MobileJourneyProbe.run(Object.new, surface, Dir.tmpdir)
  end

  def test_cdp_back_and_forward_drive_browser_history
    cdp = Class.new(Deploy::CdpSession) do
      def sent = (@sent ||= [])
      def send_cmd(method, **) = sent << method
      def evaluate(*) = "complete"
    end.new

    cdp.back(settle: 0)
    cdp.forward(settle: 0)

    assert_equal %w[Page.goBack Page.goForward], cdp.sent
  end
end
