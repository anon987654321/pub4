# frozen_string_literal: true

module Master
  module Ground
    # Runtime exposure report. Distinct from /doctor (keys, disk, git): this
    # answers whether the public face can reach personal tools without pairing.
    module SecurityAudit
      CHAT = "web/app/controllers/chat_controller.rb"
      APP = "web/app/controllers/application_controller.rb"
      REGISTRY = "lib/review/llm_dispatcher/tool_registry.rb"
      GITIGNORE = File.join(Master::ROOT, ".gitignore")

      Check = Struct.new(:ok, :name, :detail, keyword_init: true)

      module_function

      def report(root: Master::ROOT)
        rows = checks(root:)
        failed = rows.count { |row| !row.ok }
        header = failed.zero? ? "security-audit: clean" : "security-audit: #{failed} fail"
        ([header] + rows.map { |row| format_row(row) }).join("\n")
      end

      def checks(root: Master::ROOT)
        [
          pairing_required,
          pairing_store_ignored,
          allowlist_not_committed(root),
          visitor_slash_blocked,
          visitor_fiber_set,
          public_profile_has_no_shell,
          messaging_has_no_shell,
          pairing_fiber_cleared,
          gateway_remote_gated,
        ]
      end

      def pairing_required
        ok = Pairing.required_for_remote_channels?
        Check.new(ok:, name: "pairing-required", detail: ok ? "remote channels need a code" : "remote pairing is off")
      end

      def pairing_store_ignored
        body = File.exist?(GITIGNORE) ? File.read(GITIGNORE) : ""
        ok = body.match?(/^\.master\/\s*$/) || body.include?(".master/")
        Check.new(ok:, name: "pairing-gitignored", detail: ok ? ".master/ is ignored" : ".master/ missing from gitignore")
      end

      def allowlist_not_committed(root)
        path = Pairing.allowlist_path(root)
        ok = path.include?(".master/")
        Check.new(ok:, name: "allowlist-runtime", detail: ok ? path.sub("#{root}/", "") : "allowlist is not under .master/")
      end

      def visitor_slash_blocked
        body = source(CHAT)
        ok = body.include?('visitor? && input.start_with?("/")')
        Check.new(ok:, name: "visitor-slash", detail: ok ? "chat slash forbidden for visitors" : "visitor slash gate missing")
      end

      def visitor_fiber_set
        app = source(APP)
        svc = File.read(File.join(Master::ROOT, "web/app/services/chat_service.rb"))
        ok = app.include?("Fiber[:master_visitor]") && svc.include?("Fiber[:master_visitor]")
        Check.new(ok:, name: "visitor-fiber", detail: ok ? "web sets Fiber[:master_visitor]" : "visitor fiber not set")
      end

      def public_profile_has_no_shell
        names = Tool::Profile.public_names
        ok = names.none? { |name| %w[Shell WriteFile StrReplace].include?(name) }
        Check.new(ok:, name: "public-profile", detail: "public=#{names.join(',')}")
      end

      def messaging_has_no_shell
        names = Tool::Profile.messaging_names
        ok = names.none? { |name| %w[Shell WriteFile StrReplace].include?(name) }
        Check.new(ok:, name: "messaging-profile", detail: "messaging=#{names.join(',')}")
      end

      def pairing_fiber_cleared
        app = source(APP)
        svc = File.read(File.join(Master::ROOT, "web/app/services/chat_service.rb"))
        ok = app.include?("Fiber[:master_paired] = nil") && svc.include?("Fiber[:master_paired] = nil")
        Check.new(ok:, name: "paired-fiber-clear", detail: ok ? "paired flag cleared after turn" : "paired flag leak")
      end

      def gateway_remote_gated
        body = File.read(File.join(Master::ROOT, "lib/io/gateway.rb"))
        ok = body.include?("Pairing.apply_remote!")
        Check.new(ok:, name: "gateway-remote", detail: ok ? "irc/matrix apply pairing" : "gateway does not apply pairing")
      end

      def source(relative)
        File.read(File.join(Master::ROOT, relative))
      end

      def format_row(row)
        mark = row.ok ? "ok" : "FAIL"
        "#{mark}  #{row.name} — #{row.detail}"
      end
    end
  end
end
