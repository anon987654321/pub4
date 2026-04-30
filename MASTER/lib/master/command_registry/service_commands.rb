# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def control_commands(standing, soul)
      {
        "orders" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "list", ""
            standing.list
          when /\Aenable (.+)\z/
            standing.enable($1.strip)
          when /\Adisable (.+)\z/
            standing.disable($1.strip)
          when /\Aadd name=(\S+) cmd=(.+)\z/
            standing.upsert(name: $1, command: $2.strip)
          when "run"
            results = standing.run_due!
            if results.empty?
              "no orders due"
            else
              results.map { |r|
                "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}"
              }.join("\n")
            end
          when /\Areset (.+)\z/
            standing.reset($1.strip)
          else
            "usage: /orders  /orders enable|disable|reset <name>  /orders run"
          end
        },
        "soul" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "", "show" then soul.summary
          when "version", "changelog" then soul.changelog
          when "diff" then soul.diff
          when "approve" then soul.approve
          when "reject" then soul.reject
          when "rollback" then soul.rollback
          when /\Apropose (.+)\z/ then soul.propose($1.strip)
          else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
          end
        }
      }
    end

    def service_commands(ai)
      heartbeat = ai[:heartbeat]
      skills = ai[:skills]
      {
        "heartbeat" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "run"   then heartbeat ? heartbeat.run_due!.map { |r| "#{r[:name]}: #{r[:result]}" }.join("\n") : "no heartbeat"
          when "start" then heartbeat&.start!; "heartbeat started"
          when "stop"  then heartbeat&.stop!; "heartbeat stopped"
          else heartbeat&.list || "no heartbeat"
          end
        },
        "skills" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.empty?
            skills&.list || "(no skills)"
          else
            found = skills&.find(arg)
            found ? "#{found[:name]}: #{found[:description]}" : "(not found: #{arg})"
          end
        }
      }
    end

    def utility_commands(agent, root, cache)
      {
        "snapshot" => ->(_ctx) {
          stamp = Time.now.strftime("%Y%m%d_%H%M%S")
          out = File.expand_path("~/master_snapshot_#{stamp}.md")
          dirs = %w[exe lib/master web/app web/config data].map { |d| File.join(root, d) }
          files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                      .select { |f| File.file?(f) && File.size(f) < CTX_WINDOW_SIZE }
                      .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                      .reject { |f| File.binread(f, 512).include?("\x00") rescue true }
                      .sort
          lines = ["# MASTER Codebase Snapshot", "Generated: #{Time.now.utc.iso8601}", ""]
          files.each do |f|
            rel = f.sub("#{root}/", "")
            lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
            src = File.read(f, encoding: "UTF-8", invalid: :replace)
            lines << "## #{rel}" << "```#{lang}" << src.rstrip << "```" << ""
          rescue StandardError => e
            lines << "## #{rel}" << "[skipped: #{e.message}]" << ""
          end
          File.write(out, lines.join("\n"))
          "snapshot: #{files.size} files written to #{out}"
        },
        "cache" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "clear"
            cache.invalidate_all!
            "cache cleared"
          else
            stats = cache.stats
            suffix = arg == "stats" ? "" : "  (use /cache clear to purge)"
            "cache: #{stats[:entries]} entries, #{stats[:size_kb]} KB#{suffix}"
          end
        },
        "diff" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          base = arg.empty? ? "HEAD" : arg
          out = `git -C #{root.shellescape} diff #{base} --stat 2>&1`.strip
          out.empty? ? "(no changes since #{base})" : out
        },
        "commit" => ->(_ctx) {
          diff = `git -C #{root.shellescape} diff --cached --stat 2>&1`.strip
          diff = `git -C #{root.shellescape} diff --stat 2>&1`.strip if diff.empty?
          next "nothing to commit" if diff.empty?
          prompt = "Write a concise git commit message (1 line, imperative mood) for these changes:\n#{diff}"
          msg = agent.ask_once(prompt).strip.lines.first.to_s.strip.gsub(/"/, "'")
          `git -C #{root.shellescape} add -u 2>&1 && git -C #{root.shellescape} commit -m "#{msg}" 2>&1`.strip
        },
        "knowledge" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.start_with?("add ")
            url = arg.sub("add ", "").strip
            require "open-uri"
            require "shellwords"
            next "usage: /knowledge add <url>" if url.empty?
            slug = url.gsub(/[^a-z0-9._-]/i, "_").downcase[0, 60]
            kdir = File.join(root, "knowledge", "web")
            FileUtils.mkdir_p(kdir)
            dest = File.join(kdir, "#{slug}.txt")
            content = URI.open(url, read_timeout: 15, &:read)
                         .encode("UTF-8", invalid: :replace, undef: :replace)
            File.write(dest, content, encoding: "UTF-8")
            "saved #{content.bytesize} bytes to knowledge/web/#{slug}.txt"
          else
            "usage: /knowledge add <url>"
          end
        }
      }
    end
  end
end
