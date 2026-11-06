#!/usr/bin/env ruby
# frozen_string_literal: true

# Static layout drift audit for Brgen, Amber and MASTER.
#
# Run from any directory:
#   ruby MASTER/tools/rails/layout_drift_audit.rb
#   ruby MASTER/tools/rails/layout_drift_audit.rb --json
#
# This check is deliberately report-only. It does not rewrite generated CSS,
# edit layouts, commit, push, deploy, or claim rendered/browser verification.
require "json"
require "open3"
require "rbconfig"

module Operator
  class LayoutDriftAudit
    Finding = Struct.new(:status, :code, :path, :line, :message, keyword_init: true)

    attr_reader :root, :findings

    def initialize(root: self.class.repository_root)
      @root = File.expand_path(root)
      @findings = []
    end

    def self.repository_root(start = __dir__)
      current = File.expand_path(start)
      loop do
        return current if File.file?(File.join(current, "MASTER/data/soul.yml")) &&
                          File.file?(File.join(current, "MASTER/data/laws.yml")) &&
                          File.directory?(File.join(current, "RAILS"))

        parent = File.dirname(current)
        raise "layout_audit: could not locate repository root from #{start}" if parent == current

        current = parent
      end
    end

    def run
      findings.clear
      audit_authority
      audit_shared_post_cards
      audit_feed_lists
      audit_playlist_empty_state
      audit_master_face
      audit_document_landmarks
      findings << Finding.new(
        status: "NOT_RUN", code: "rendered_visual",
        path: "RAILS", message: "Rendered mobile/desktop comparison and real screen-reader testing require a browser session."
      )
      findings << Finding.new(
        status: "NOT_RUN", code: "runtime_suites",
        path: "RAILS", message: "Rails app suites are not run by this static source audit."
      )
      findings
    end

    def report(json: false, io: $stdout)
      run if findings.empty?
      if json
        io.puts JSON.pretty_generate(
          repository: root,
          summary: summary,
          findings: findings.map(&:to_h)
        )
      else
        findings.each do |finding|
          location = finding.path.to_s
          location = "#{location}:#{finding.line}" if finding.line
          io.puts "#{finding.status.downcase}0: #{finding.code} #{location} - #{finding.message}"
        end
        counts = summary
        io.puts "layout0: PASS=#{counts.fetch('PASS')} FAIL=#{counts.fetch('FAIL')} NOT_RUN=#{counts.fetch('NOT_RUN')}"
      end
      exit_status
    end

    def summary
      %w[PASS FAIL NOT_RUN].to_h do |status|
        [status, findings.count { |finding| finding.status == status }]
      end
    end

    def exit_status
      findings.any? { |finding| finding.status == "FAIL" } ? 1 : 0
    end

    # ERB output expressions can contain '>' characters. Mask them before
    # scanning opening tags so a comparison in Ruby cannot truncate the tag.
    def feed_list_entries(source)
      sanitized = source.to_s.gsub(/<%#.*?%>/m, "").gsub(/<%=.*?%>/m, " ERB_VALUE ")
      pattern = /<ul\b[^>]*\bfeed_list\b[^>]*>/m
      entries = []
      offset = 0
      while (match = pattern.match(sanitized, offset))
        line = sanitized[0...match.begin(0)].count("\n") + 1
        entries << [match[0], line]
        offset = match.end(0)
      end
      entries
    end

    def feed_list_open_tags(source)
      feed_list_entries(source).map(&:first)
    end

    def feed_list_violations(source)
      feed_list_entries(source).reject { |tag, _line| tag.match?(/\brole\s*=\s*["']list["']/) }
    end

    private

    def file(path)
      File.join(root, path)
    end

    def read(path)
      File.read(file(path), encoding: "UTF-8")
    rescue Errno::ENOENT
      nil
    end

    def add(status, code, path, message, source: nil, needle: nil)
      line = if source && needle
               index = source.index(needle)
               index && source[0...index].count("\n") + 1
             end
      findings << Finding.new(status:, code:, path:, line:, message:)
    end

    def expect(code, path, source, needle, message)
      if source&.include?(needle)
        add("PASS", code, path, message, source:, needle:)
      else
        add("FAIL", code, path, message, source:)
      end
    end

    def audit_authority
      soul_path = "MASTER/data/soul.yml"
      laws_path = "MASTER/data/laws.yml"
      soul = read(soul_path)
      laws = read(laws_path)
      expect("authority.soul", soul_path, soul, "constitution: MASTER/data/laws.yml",
             "soul.yml must declare laws.yml as its constitutional authority.")
      expect("authority.preserve_first", soul_path, soul, "golden_law: PRESERVE_FIRST",
             "The preservation law must remain the governing golden law.")
      expect("authority.preserve_first_law", laws_path, laws, "PRESERVE_FIRST:",
             "The governing preservation law must exist in the law catalogue.")
      expect("authority.css_law", "MASTER/law/css.rb", read("MASTER/law/css.rb"), "MOBILE_VIEWPORT",
             "The CSS law source must retain mobile viewport coverage.")
      expect("authority.universal_law", "MASTER/law/universal.rb", read("MASTER/law/universal.rb"), "44 CSS px",
             "The universal law source must retain the primary touch target guidance.")
    end

    def audit_shared_post_cards
      shared_view_path = "RAILS/__shared/app/views/shared/_post_card.html.erb"
      shared_css_path = "RAILS/__shared/app/assets/stylesheets/_post_voting.scss"
      shared_view = read(shared_view_path)
      shared_css = read(shared_css_path)

      %w[brgen amber].each do |app|
        view_path = "RAILS/#{app}/app/views/posts/_post.html.erb"
        view = read(view_path)
        expect("post_card.shared_renderer.#{app}", view_path, view, 'render "shared/post_card"',
               "#{app} must use the shared post-card renderer.")
        expect("post_card.votes.#{app}", view_path, view, "show_votes: true",
               "#{app} must retain the shared voting rail.")
        add("FAIL", "post_card.variant.#{app}", view_path,
            "App-specific post-card variants reintroduce visual drift.", source: view) if view&.match?(/\bvariant\s*:/)
      end

      expect("post_card.shared_markup", shared_view_path, shared_view, 'class: "feed-card post-reading-card"',
             "The shared post renderer must own the common card identity.")
      expect("post_card.vote_rail", shared_view_path, shared_view, 'render "shared/post_vote_rail"',
             "The shared post renderer must own the vote rail.")
      expect("post_card.mobile_spacing", shared_css_path, shared_css, "padding: var(--space-4) var(--space-3);",
             "The shared card must define its mobile spacing.")
      expect("post_card.desktop_spacing", shared_css_path, shared_css, "padding: var(--space-5) var(--space-4);",
             "The shared card must define its wider-screen spacing.")
      expect("post_card.shared_actions", shared_css_path, shared_css,
             ".feed-card.post-reading-card .feed-card-actions",
             "Post action geometry must remain scoped to the shared post card.")
      expect("post_card.touch_targets", shared_css_path, shared_css, "min-inline-size: var(--tap-min);",
             "Author and title links must retain the shared tap floor.")

      %w[stack stack_brgen].each do |stack|
        path = "RAILS/__shared/app/assets/stylesheets/_#{stack}.scss"
        expect("post_card.stack.#{stack}", path, read(path), '@forward "post_voting";',
               "Both app stacks must load the same post-card structure.")
      end

      amber_css_path = "RAILS/amber/app/assets/stylesheets/application.scss"
      restyled = read(amber_css_path).to_s.match?(/\.feed-card[^{,]*\.post-reading-title/)
      add(restyled ? "FAIL" : "PASS", "post_card.amber_detail_type", amber_css_path,
          "Amber must keep the shared feed card's title face; its post page h1 is visually hidden.")
    end

    def audit_feed_lists
      paths = Dir.glob(file("RAILS/**/*.erb")).sort
      if paths.empty?
        add("FAIL", "feed_lists.scan", "RAILS", "No ERB views were found under RAILS.")
        return
      end

      total = 0
      paths.each do |absolute|
        source = File.read(absolute, encoding: "UTF-8")
        tags = feed_list_open_tags(source)
        next if tags.empty?

        total += tags.length
        missing = feed_list_violations(source)
        missing.each do |_tag, line|
          findings << Finding.new(
            status: "FAIL", code: "feed_lists.role",
            path: absolute.delete_prefix("#{root}/"), line:,
            message: "Every markerless feed_list needs role=\"list\" for consistent list exposure."
          )
        end
      end

      add("PASS", "feed_lists.role", "RAILS", "Every discovered feed_list declares role=\"list\".") if total.positive? &&
        findings.none? { |finding| finding.code == "feed_lists.role" && finding.status == "FAIL" }

      css_path = "RAILS/__shared/app/assets/stylesheets/_feed_list.scss"
      css = read(css_path)
      expect("feed_lists.post_item_boxes", css_path, css,
             ".feed_list.post-card-list > li {\n  display: block;",
             "Linear post feeds must retain real list-item boxes.")
    end

    def audit_playlist_empty_state
      path = "RAILS/brgen_radio/playlist/app/views/playlist/playlists/_library.html.erb"
      source = read(path)
      empty = source&.index('render "shared/empty_state"')
      close_list = source&.index("</ul>")
      valid = source && empty && close_list && empty > close_list
      add(valid ? "PASS" : "FAIL", "playlist.empty_state", path,
          "The empty state must be outside the playlist ul.")
    end

    def audit_master_face
      source_path = "MASTER/web/styles/face/30_conversation.css"
      chrome_path = "MASTER/web/styles/face/60_session_chrome.css"
      public_path = "MASTER/web/public/face.css"
      source = read(source_path)
      chrome = read(chrome_path)
      public_css = read(public_path)

      expect("master.history.mobile_clearance", source_path, source,
             "bottom: calc(76px + var(--safe-bottom) + var(--keyboard-inset, 0px));",
             "The mobile history drawer must clear the prompt, safe area and keyboard.")
      expect("master.history.wide_clearance", chrome_path, chrome,
             "#chat-history-panel { bottom: calc(80px + var(--safe-bottom) + var(--keyboard-inset, 0px)); }",
             "The wider history drawer must clear the taller prompt.")
      expect("master.history.generated_mobile", public_path, public_css,
             "bottom: calc(76px + var(--safe-bottom) + var(--keyboard-inset, 0px));",
             "The generated face bundle must contain the mobile history clearance.")
      expect("master.history.generated_wide", public_path, public_css,
             "#chat-history-panel { bottom: calc(80px + var(--safe-bottom) + var(--keyboard-inset, 0px)); }",
             "The generated face bundle must contain the wider history clearance.")

      builder = file("MASTER/tools/rails/build_face_css.rb")
      if File.file?(builder)
        out, err, status = Open3.capture3(RbConfig.ruby, builder, "--check", chdir: root)
        message = status.success? ? "public/face.css matches the ordered editable source modules." :
          "Generated face CSS differs from source modules: #{(out + err).strip}"
        add(status.success? ? "PASS" : "FAIL", "master.face.generated_parity",
            "MASTER/web/public/face.css", message)
      else
        add("FAIL", "master.face.generated_parity", "MASTER/tools/rails/build_face_css.rb",
            "The canonical face CSS builder is missing.")
      end
    end

    def audit_document_landmarks
      {
        "brgen" => "RAILS/brgen/app/views/layouts/application.html.erb",
        "amber" => "RAILS/amber/app/views/layouts/application.html.erb"
      }.each do |app, path|
        source = read(path)
        %w[class="skip-link" id="main-content" data-layout="document"].each do |needle|
          expect("landmark.#{app}.#{needle}", path, source, needle,
                 "#{app} must retain its skip link, document layout and main landmark.")
        end
      end

      chat_path = "MASTER/web/app/views/chat/index.html.erb"
      chat = read(chat_path)
      expect("landmark.master_chat", chat_path, chat, 'href="#prompt-input"',
             "MASTER chat must offer a skip link to its prompt.")
      expect("landmark.master_chat_main", chat_path, chat, '<main id="chat-shell"',
             "MASTER chat must retain its named main landmark.")
      expect("landmark.master_chat_prompt", chat_path, chat, '<textarea id="prompt-input"',
             "MASTER chat must retain the keyboard-accessible prompt.")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  json = ARGV.include?("--json")
  audit = Operator::LayoutDriftAudit.new
  audit.run
  exit audit.report(json:)
end
