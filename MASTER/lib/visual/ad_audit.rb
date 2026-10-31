# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

module Master
  module Visual
    # Deterministic visual law detectors and the fail-closed renderer gate.
    # Browser facts are supplied as evidence by the renderer; missing evidence
    # is a failure, never an inferred pass.
    module AdAudit
      LAW_IDS = %w[
        VISUAL_IDENTITY_TOKENS_ONLY VISUAL_CONTRAST_WCAG_AA
        VISUAL_DISCLOSURE_PROMINENCE VISUAL_ALT_TEXT_PRESENT
        VISUAL_SAFE_ZONE_RESPECTED VISUAL_RENDER_INTEGRITY
      ].freeze
      REQUIRED_BOUNDS = %w[headline logo cta].freeze
      REPORT_SCHEMA_VERSION = 1
      POLICY_SOURCE_PATH = File.expand_path("../../data/laws.yml", __dir__).freeze
      DETECTOR_SOURCE_PATH = File.expand_path(__FILE__).freeze
      MEASUREMENT_SOURCE_PATH = File.expand_path("../../tools/visual/browserless_measurements.rb", __dir__).freeze
      module_function

      def contract(path: File.expand_path("../../data/tokens.yml", __dir__))
        data = YAML.safe_load_file(path, aliases: true)
        value = data.fetch("tokens").fetch("ad_visual_contract")
        raise ArgumentError, "ad visual contract version must be positive" unless Integer(value.fetch("version")).positive?
        value
      end

      def token_version(contract = self.contract)
        Digest::SHA256.hexdigest(JSON.generate(deep_sort(contract)))
      end

      # Bind each result to the exact policy, detector and measurement source.
      # The receipt is a checksum, not a signature or proof that caller-supplied
      # renderer evidence is truthful.
      def seal!(report, rendered: nil)
        raise ArgumentError, "audit report must be a Hash" unless report.is_a?(Hash)

        report.delete(:provenance)
        report.delete("provenance")
        report.delete(:evidence_sha256)
        report.delete("evidence_sha256")
        report[:provenance] = {
          schema_version: REPORT_SCHEMA_VERSION,
          policy_sha256: file_sha256(POLICY_SOURCE_PATH),
          detector_sha256: file_sha256(DETECTOR_SOURCE_PATH),
          measurement: measurement_provenance(rendered),
        }
        report[:evidence_sha256] = evidence_digest(report)
        report
      end

      def verify_evidence!(report)
        status = receipt_status(report)
        return true if status == :valid

        message = {
          missing: "visual audit evidence receipt is missing",
          tampered: "visual audit report changed after it was sealed",
          policy_stale: "visual audit Law catalogue has changed",
          detector_stale: "visual audit detector source has changed",
          measurement_stale: "browserless measurement source has changed",
          invalid: "visual audit evidence receipt is invalid",
        }.fetch(status, "visual audit evidence receipt is invalid")
        raise VisualAuditRejected, message
      end

      def audit(html:, css:, placement:, rendered: nil, token_contract: self.contract)
        checks = [
          identity_tokens(html:, css:, token_contract:),
          contrast(token_contract:, rendered:),
          disclosure(html:, rendered:, token_contract:),
          alt_text(html:),
          safe_zone(placement:, rendered:),
          render_integrity(rendered:, token_contract:),
        ]
        seal!(
          {
            passed: checks.all? { |check| check.fetch(:pass) },
            token_version: token_version(token_contract),
            placement: placement.to_s,
            checks:,
          },
          rendered:,
        )
      end

      def require_pass!(report, current_contract: self.contract, placement:)
        raise VisualAuditRejected, "visual audit report missing" unless report.is_a?(Hash)

        verify_evidence!(report)
        checks = report[:checks] || report["checks"] || []
        passed = report.is_a?(Hash) ? (report[:passed] || report["passed"]) : false
        version = report.is_a?(Hash) ? (report[:token_version] || report["token_version"]) : nil
        report_placement = report.is_a?(Hash) ? (report[:placement] || report["placement"]) : nil
        complete = LAW_IDS.all? do |law|
          checks.any? do |check|
            check_law = check[:law] || check["law"]
            check_pass = check[:pass] || check["pass"]
            check_law == law && check_pass == true
          end
        end
        unless report.is_a?(Hash) && passed == true &&
               version == token_version(current_contract) &&
               report_placement.to_s == placement.to_s && complete
          raise VisualAuditRejected, rejection_reason(report, current_contract, placement)
        end
        true
      end

      def identity_tokens(html:, css:, token_contract:)
        prefix = Regexp.escape(token_contract.fetch("token_prefix", "ad-organ"))
        scoped = css.to_s.scan(/\.[\w-]*#{prefix}[\w-]*\s*\{[^}]*\}/m).join("\n")
        bad_colors = scoped.scan(/(?:^|[;{])\s*(?:color|background(?:-color)?|border(?:-[\w-]+)?-color|outline-color)\s*:\s*(?!var\s*\()[^;}]+/i).flatten
        bad_colors.reject! { |value| value.match?(/\A\s*(?:transparent|currentColor|inherit|initial|unset)\s*\z/i) }
        bad_font = scoped.match?(/font-family\s*:\s*(?!var\s*\()[^;}]+/i)
        bad_spacing = scoped.scan(/(?:^|[;{])\s*(?:margin|padding|gap|border-radius)(?:-[\w-]+)?\s*:\s*(?!var\s*\()[^;}]+/i)
        reasons = []
        reasons << "hardcoded colour declaration in ad-organ CSS" if bad_colors.any?
        reasons << "font-family must resolve through a token" if bad_font
        reasons << "spacing/radius declaration must resolve through a token" if bad_spacing.any?
        result("VISUAL_IDENTITY_TOKENS_ONLY", reasons)
      end

      def contrast(token_contract:, rendered:)
        reasons = []
        %w[light dark].each do |mode|
          token_contract.fetch("contrast_pairs").each do |pair|
            fg = resolve_color(token_contract, pair.fetch("foreground"), mode)
            bg = resolve_color(token_contract, pair.fetch("background"), mode)
            ratio = contrast_ratio(fg, bg)
            reasons << "#{mode} token pair #{pair['foreground']}/#{pair['background']} is #{ratio.round(2)}:1; requires #{pair['minimum']}:1" if ratio < pair.fetch("minimum").to_f
          end
        end
        pairs = rendered.is_a?(Hash) ? Array(rendered[:contrast_pairs] || rendered["contrast_pairs"]) : []
        reasons << "rendered contrast evidence is missing" if pairs.empty?
        pairs.each_with_index do |pair, index|
          ratio = pair[:ratio] || pair["ratio"]
          minimum = pair[:minimum] || pair["minimum"] || 4.5
          reasons << "rendered contrast pair #{index + 1} is missing a measured ratio" unless ratio.is_a?(Numeric)
          reasons << "rendered contrast pair #{index + 1} is below #{minimum}:1" if ratio.is_a?(Numeric) && ratio < minimum.to_f
        end
        result("VISUAL_CONTRAST_WCAG_AA", reasons)
      end

      def disclosure(html:, rendered:, token_contract:)
        reasons = []
        found = html.to_s.match?(/(?:class|data-visual-role)\s*=\s*["'][^"']*(?:ad-organ-disclosure|disclosure)[^"']*["']/i) &&
                html.to_s.match?(/>\s*(?:ad|advertisement|sponsored|paid partnership)\s*</i)
        reasons << "commercial disclosure element is missing or has no recognised label" unless found
        evidence = rendered.is_a?(Hash) ? (rendered[:disclosure] || rendered["disclosure"]) : nil
        reasons << "rendered disclosure position/contrast evidence is missing" unless evidence.is_a?(Hash)
        if evidence.is_a?(Hash)
          distance = evidence[:distance_px] || evidence["distance_px"]
          ratio = evidence[:contrast_ratio] || evidence["contrast_ratio"]
          minimum = token_contract.fetch("contrast_pairs").find { |p| p["foreground"] == "disclosure_foreground" }&.fetch("minimum", 4.5).to_f
          reasons << "disclosure distance is not measured" unless distance.is_a?(Numeric)
          reasons << "disclosure is too far from creative" if distance.is_a?(Numeric) && distance > token_contract.dig("placement", "disclosure_max_distance").to_f
          reasons << "disclosure contrast is not measured" unless ratio.is_a?(Numeric)
          reasons << "disclosure contrast is below #{minimum}:1" if ratio.is_a?(Numeric) && ratio < minimum
          reasons << "disclosure font is too small" if (evidence[:font_size_px] || evidence["font_size_px"]).to_f < 12
        end
        result("VISUAL_DISCLOSURE_PROMINENCE", reasons)
      end

      def alt_text(html:)
        reasons = []
        html.to_s.scan(/<img\b[^>]*>/im).each_with_index do |tag, index|
          alt = tag.match(/\balt\s*=\s*(["'])(.*?)\1/im)
          decorative = tag.match?(/\brole\s*=\s*["']presentation["']/i) || tag.match?(/\baria-hidden\s*=\s*["']true["']/i)
          reasons << "image #{index + 1} has no non-empty alt text" if !decorative && (!alt || alt[2].strip.empty?)
        end
        result("VISUAL_ALT_TEXT_PRESENT", reasons)
      end

      def safe_zone(placement:, rendered:)
        reasons = []
        evidence = rendered.is_a?(Hash) ? (rendered[:safe_zone] || rendered["safe_zone"]) : nil
        reasons << "rendered safe-zone evidence is missing" unless evidence.is_a?(Hash)
        if evidence.is_a?(Hash)
          safe = evidence[:rect] || evidence["rect"]
          bounds = evidence[:bounds] || evidence["bounds"]
          reasons << "safe-zone rectangle is missing" unless safe.is_a?(Hash)
          reasons << "headline/logo/CTA bounds are missing" unless bounds.is_a?(Hash)
          if safe.is_a?(Hash) && bounds.is_a?(Hash)
            REQUIRED_BOUNDS.each do |name|
              box = bounds[name] || bounds[name.to_sym]
              reasons << "#{name} bounds are missing" unless box.is_a?(Hash)
              next unless box.is_a?(Hash)
              %w[x y width height].each { |key| reasons << "#{name} #{key} is missing" unless numeric_key?(box, key) }
              next unless %w[x y width height].all? { |key| numeric_key?(box, key) }
              left = numeric_value(safe, "x")
              top = numeric_value(safe, "y")
              width = numeric_value(safe, "width")
              height = numeric_value(safe, "height")
              unless [left, top, width, height].all? { |value| value.is_a?(Numeric) }
                reasons << "safe-zone rectangle has incomplete geometry"
                next
              end
              inside = numeric_value(box, "x") >= left && numeric_value(box, "y") >= top &&
                       numeric_value(box, "x") + numeric_value(box, "width") <= left + width &&
                       numeric_value(box, "y") + numeric_value(box, "height") <= top + height
              reasons << "#{name} extends outside placement safe zone" unless inside
            end
          end
        end
        result("VISUAL_SAFE_ZONE_RESPECTED", reasons)
      end

      def render_integrity(rendered:, token_contract:)
        reasons = []
        evidence = rendered.is_a?(Hash) ? (rendered[:integrity] || rendered["integrity"]) : nil
        reasons << "render integrity evidence is missing" unless evidence.is_a?(Hash)
        if evidence.is_a?(Hash)
          reasons << "one or more rendered assets failed to load" unless (evidence[:assets_loaded] || evidence["assets_loaded"]) == true
          bytes = evidence[:transfer_bytes] || evidence["transfer_bytes"]
          max_bytes = token_contract.dig("render", "max_transfer_bytes").to_i
          reasons << "transfer size is not measured" unless bytes.is_a?(Numeric)
          reasons << "transfer size exceeds #{max_bytes} bytes" if bytes.is_a?(Numeric) && bytes > max_bytes
          cls = evidence[:cumulative_layout_shift] || evidence["cumulative_layout_shift"]
          max_cls = token_contract.dig("render", "max_cumulative_layout_shift").to_f
          static_status = (rendered[:measurement_mode] || rendered["measurement_mode"]) == "browserless_static" ? (defined?(Master::Visual::BrowserlessMeasurements) ? Master::Visual::BrowserlessMeasurements.static_render_integrity_status(rendered) : :invalid) : :not_static
          reasons << (static_status == :invalid ? "browserless mode cannot claim measured CLS or incomplete proof" : "cumulative layout shift is not measured") unless (cls.is_a?(Numeric) && static_status != :invalid) || static_status == :valid
          reasons << "cumulative layout shift exceeds #{max_cls}" if static_status != :invalid && cls.is_a?(Numeric) && cls > max_cls
          reasons << "render completion is not confirmed" unless (evidence[:rendered] || evidence["rendered"]) == true || static_status == :valid
        end
        result("VISUAL_RENDER_INTEGRITY", reasons)
      end

      def contrast_ratio(foreground, background)
        l1, l2 = [luminance(foreground), luminance(background)].sort.reverse
        (l1 + 0.05) / (l2 + 0.05)
      end

      def luminance(hex)
        value = hex.to_s.delete_prefix("#")
        raise ArgumentError, "expected #RRGGBB colour, got #{hex.inspect}" unless value.match?(/\A[0-9a-f]{6}\z/i)
        channels = value.scan(/../).map { |part| part.to_i(16) / 255.0 }
        channels.map! { |channel| channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4 }
        channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
      end

      def resolve_color(contract, role, mode)
        contract.fetch("colors").fetch(role).fetch(mode)
      end

      def numeric_value(hash, key) = hash[key] || hash[key.to_sym]

      def numeric_key?(hash, key) = numeric_value(hash, key).is_a?(Numeric)

      def result(law, reasons)
        { law:, pass: reasons.empty?, reasons: reasons.freeze }
      end

      def rejection_reason(report, current_contract, placement)
        return "visual audit report missing" unless report.is_a?(Hash)
        return "visual audit failed" unless (report[:passed] || report["passed"]) == true
        return "visual audit token version is stale" unless (report[:token_version] || report["token_version"]) == token_version(current_contract)
        return "visual audit placement does not match" unless (report[:placement] || report["placement"]).to_s == placement.to_s
        "visual audit is incomplete"
      end

      def deep_sort(value)
        case value
        when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
        when Array then value.map { |item| deep_sort(item) }
        else value
        end
      end

      def receipt_status(report)
        return :missing unless report.is_a?(Hash)

        supplied = read_value(report, :evidence_sha256)
        provenance = read_value(report, :provenance)
        return :missing unless supplied.is_a?(String) && provenance.is_a?(Hash)
        return :tampered unless evidence_digest(report) == supplied
        return :invalid unless read_value(provenance, :schema_version) == REPORT_SCHEMA_VERSION
        return :policy_stale unless read_value(provenance, :policy_sha256) == file_sha256(POLICY_SOURCE_PATH)
        return :detector_stale unless read_value(provenance, :detector_sha256) == file_sha256(DETECTOR_SOURCE_PATH)

        measurement = read_value(provenance, :measurement)
        return :invalid unless measurement.is_a?(Hash)
        if read_value(measurement, :mode) == "browserless_static"
          return :measurement_stale unless read_value(measurement, :source_sha256) == file_sha256(MEASUREMENT_SOURCE_PATH)
          return :invalid unless read_value(measurement, :version).is_a?(Integer)
        end
        :valid
      rescue StandardError
        :invalid
      end

      def measurement_provenance(rendered)
        return { mode: "missing", verification: "no_rendered_evidence" } unless rendered.is_a?(Hash)

        mode = read_value(rendered, :measurement_mode).to_s
        mode = "caller_supplied" if mode.empty?
        details = {
          mode: mode,
          version: read_value(rendered, :measurement_version),
          verification: "caller_supplied_unverified",
        }
        if mode == "browserless_static"
          details[:source_sha256] = file_sha256(MEASUREMENT_SOURCE_PATH)
          details[:verification] = "repository_source_digest"
        end
        details
      end

      def evidence_digest(report)
        unsigned = report.reject { |key, _value| key.to_s == "evidence_sha256" }
        canonical = canonical_value(unsigned)
        Digest::SHA256.hexdigest(JSON.generate(canonical))
      end

      # JSON object keys are normalized and sorted so symbol-keyed Ruby reports
      # and string-keyed JSON round-trips produce the same digest.
      def canonical_value(value)
        case value
        when Hash
          normalized = {}
          value.each do |key, item|
            name = key.to_s
            raise ArgumentError, "duplicate normalized evidence key: #{name}" if normalized.key?(name)

            normalized[name] = canonical_value(item)
          end
          normalized.sort.to_h
        when Array
          value.map { |item| canonical_value(item) }
        when Symbol
          value.to_s
        else
          value
        end
      end

      def read_value(hash, key)
        return unless hash.is_a?(Hash)
        return hash[key] if hash.key?(key)

        hash[key.to_s]
      end

      def file_sha256(path)
        raise IOError, "evidence source missing: #{path}" unless File.file?(path)

        Digest::SHA256.file(path).hexdigest
      end

      class VisualAuditRejected < StandardError; end
    end
  end
end
