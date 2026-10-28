# frozen_string_literal: true

module Master
  module Ground
    # Runtime exposure report. Distinct from /doctor (keys, disk, git): this
    # answers whether the public face can reach personal tools without pairing.
    module SecurityAudit
      CHAT = "../RAILS/master/app/controllers/chat_controller.rb"
      APP = "../RAILS/master/app/controllers/application_controller.rb"
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
        previous_visitor = Fiber[:master_visitor]
        Fiber[:master_visitor] = true
        result = Master::CLI::TurnRouter.call(message: "/fix", container: {})
        ok = result.err? && result.category == :policy && result.message.to_s.match?(/visitors/i)
        detail = ok ? "TurnRouter rejects /fix before command dispatch" : "TurnRouter did not reject visitor slash input at the shared boundary"
        Check.new(ok:, name: "visitor-slash", detail:)
      rescue StandardError => e
        Check.new(ok: false, name: "visitor-slash", detail: "behavior probe failed: #{e.class}: #{e.message}")
      ensure
        Fiber[:master_visitor] = previous_visitor
      end

      def visitor_fiber_set
        app = source(APP)
        svc = File.read(File.join(Master::ROOT, "../RAILS/master/app/services/chat_service.rb"))
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
        svc = File.read(File.join(Master::ROOT, "../RAILS/master/app/services/chat_service.rb"))
        ok = app.include?("Fiber[:master_paired] = nil") && svc.include?("Fiber[:master_paired] = nil")
        Check.new(ok:, name: "paired-fiber-clear", detail: ok ? "paired flag cleared after turn" : "paired flag leak")
      end

      def gateway_remote_gated
        previous = { visitor: Fiber[:master_visitor], paired: Fiber[:master_paired],
                     elevated: Fiber[:master_elevated], subject: Fiber[:master_pair_subject] }
        Fiber[:master_visitor] = nil
        Fiber[:master_paired] = nil
        Fiber[:master_elevated] = nil
        Fiber[:master_pair_subject] = nil
        gateway = Master::Io::Gateway.new(pipeline: nil, session: nil)
        gateway.receive(channel: :irc, message: "status")
        ok = Fiber[:master_visitor] == true
        Check.new(ok:, name: "gateway-remote", detail: ok ? "unpaired IRC turn becomes a visitor" : "unpaired IRC turn was not restricted")
      rescue StandardError => e
        Check.new(ok: false, name: "gateway-remote", detail: "behavior probe failed: #{e.class}: #{e.message}")
      ensure
        Fiber[:master_visitor] = previous[:visitor] if previous
        Fiber[:master_paired] = previous[:paired] if previous
        Fiber[:master_elevated] = previous[:elevated] if previous
        Fiber[:master_pair_subject] = previous[:subject] if previous
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
