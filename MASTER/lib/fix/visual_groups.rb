# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "fix_loop/order"

module Master
  module Fix
    # One RAILS layout sweep reported 2,741 rendered findings from a handful of causes. A group
    # is one cause, repaired once, with its members as evidence; its key is what a repair would
    # change (see key_for).
    module VisualGroups
      FIELDS = %i[key id law file selector locator impact members surfaces fix fix_detail before after].freeze

      Group = Struct.new(*FIELDS, keyword_init: true) do
        def member_count = members.size

        def runtime? = impact == :runtime

        def repaired? = %i[mechanical model].include?(fix)

        # The findings themselves, for the model: a few in full and the size of the rest.
        def evidence(limit = 8)
          shown = members.first(limit).map { |row| "- #{row}" }
          shown << "- (#{members.size - limit} more like these)" if members.size > limit
          shown.join("\n")
        end

        def routes = surfaces.map { |id| id.sub(%r{/[^/]+\z}, "") }.uniq.first(5)

        def viewports = surfaces.map { |id| id.split("/").last }.uniq

        # One row of visual_groups.json, the input of a before/after review page.
        def to_report
          {
            "id" => id, "key" => key, "law" => law, "impact" => impact.to_s, "file" => file,
            "selector" => selector, "locator" => locator, "members" => member_count,
            "examples" => members.first(3), "routes" => routes, "viewports" => viewports,

            "fix" => fix.to_s, "fix_detail" => fix_detail, "before" => before, "after" => after
          }
        end
      end

      LABELS = /\A((?:\[[A-Za-z]\w*\]\s*)+)/
      SURFACE = %r{\b([a-z][\w-]*)/([\w.-]+)/(mobile|compact|desktop|tablet|wide)\b}
      URL = %r{https?://[^\s)'"]+}
      FILE = %r{(?<![\w/.-])((?:[\w.-]+/)*[\w.-]+\.(?:scss|css|erb|js))\b}
      SELECTOR = /(?<![\w\/.#-])(?:[a-z][a-z0-9]*)?(?:[.#][A-Za-z_][\w-]+)+/
      HEX = /\A#\h{3,8}\z/
      HTTP_STATUS = /\b(?:HTTP|status of) ([45]\d\d)\b/
      # Composite summary lines restate their leaves; grouping them would count a cause twice.
      SUMMARY = /\A(?:layout_suite|rendered_suite):/

      module_function

      # findings: the sweep's failure and soft-failure lines. urls: surface id => page URL, so a
      # document that answered 404 and the console line about that same URL meet in one group.
      def build(findings, urls: {})
        groups = {}

        Array(findings).filter_map { |text| parse(text, urls:) }.each do |row|
          absorb(groups[row[:key]] ||= open_group(row), row)
        end
        ranked(groups.values)
      end

      def absorb(group, row)
        group.members << row[:body]
        group.surfaces |= row[:surfaces]
        group.impact = :runtime if row[:impact] == :runtime
      end

      # What users meet first, then the biggest cause, then the key for a stable order.
      def ranked(groups)
        tiers = FixLoop::LawOrder::IMPACT_TIERS
        groups.sort_by { |group| [tiers.index(group.impact), -group.member_count, group.key] }
      end

      def open_group(row)
        Group.new(**row.slice(:key, :law, :file, :selector, :locator, :impact),
                  id: Digest::SHA256.hexdigest(row[:key])[0, 12], members: [], surfaces: [],
                  fix: :none, fix_detail: nil, before: [], after: [])
      end

      def parse(text, urls: {})
        line = text.to_s.strip.delete_prefix("[soft→hard]").strip
        body = line.sub(LABELS, "")
        return if body.empty? || body.match?(SUMMARY)

        row = described(body, labels: line[LABELS, 1].to_s, urls:)
        row.merge(key: key_for(row))
      end

      def described(body, labels:, urls:)
        surfaces = body.scan(SURFACE).map { |parts| parts.join("/") }.uniq
        impact = impact_of(body)
        url = body[URL] || urls[surfaces.first] || surfaces.first.to_s.sub(%r{/[^/]+\z}, "")
        { law: law_for(labels, body), impact:, surfaces:, body:, locator: locator_for(body, url:),
          **places(body, impact) }
      end

      # Everything the sweep found is on a page; what is not a broken page is a rendered defect.
      def impact_of(body)
        tier = FixLoop::LawOrder::IMPACT_TIERS.fetch(FixLoop::LawOrder.impact({ message: body }))
        tier == :runtime ? :runtime : :rendered
      end

      # The stylesheet or partial a finding names, and its selector. A stack frame reads like a
      # selector (controller.connect), so only a rendered finding is asked for one.
      def places(body, impact)
        bare = body.gsub(URL, " ").gsub(SURFACE, " ")
        selector = selector_in(bare.gsub(FILE, " ")) if impact == :rendered
        { file: bare[FILE, 1], selector: }
      end

      # The law that measured it, plus the stylesheet, the selector, or for a broken route the URL
      # that answered; a finding naming none of those is keyed by its message with surfaces, URLs
      # and numbers taken out.
      def key_for(row)
        located = row.values_at(:file, :selector, :locator).compact
        [row[:law], *located, (template(row[:body]) if located.empty?)].compact.join(" | ")
      end

      # The leaf that measured it and the check's own name for what it saw.
      def law_for(labels, body)
        kind = body[/\A([a-z][a-z_]*(?: [a-z][a-z_]*)?):/, 1]
        law = [labels.scan(/\[(\w+)\]/).flatten.last, kind].compact.join("/")
        law.empty? ? "rendered" : law
      end

      def selector_in(text)
        text.scan(SELECTOR).find { |token| !token.match?(HEX) && token.match?(/[.#][A-Za-z_][\w-]+\z/) }
      end

      # A broken route is its own cause: the URL that answered 4xx/5xx, ids folded so
      # /communities/30 and /communities/31 are one route.
      def locator_for(body, url:)
        status = body[HTTP_STATUS, 1] or return

        place = url.sub(%r{\Ahttps?://}, "").sub(/[?#].*\z/, "")
        "HTTP #{status} #{place.split("/").map { |part| part.match?(/\A\d+\z/) ? ":id" : part }.join("/")}"
      end

      def template(body)
        body.sub(/\A[^:]*:\s*#{SURFACE.source}\s*—\s*/o, "")
            .gsub(URL, "<url>").gsub(SURFACE, "<surface>").gsub(/\d+(?:\.\d+)?/, "N").squeeze(" ").strip[0, 200]
      end

      # The report a before/after review page is built from.
      def report(groups, lane:, sweeps:)
        {
          "generated_at" => Time.now.utc.iso8601, "lane" => lane.to_s,
          "findings" => groups.sum(&:member_count), "groups" => groups.size,

          "sweep" => sweeps[:before], "resweep" => sweeps[:after],
          "fixes" => groups.group_by { |group| group.fix.to_s }.transform_values(&:size),
          "rows" => groups.map(&:to_report)
        }
      end

      def write(path, report)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(report) + "\n")
        path
      end
    end
  end
end
