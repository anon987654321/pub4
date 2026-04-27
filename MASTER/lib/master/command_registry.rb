# frozen_string_literal: true

module Master
  # CommandRegistry — all pipeline-routable commands in one place.
  module CommandRegistry
    module_function

    def build(infra:, ai:, root:)
      session_commands(infra).merge(
        mode_commands(infra[:config]),
        agent_commands(ai:, root:, infra:),
        memory_commands(infra[:memory], ai[:agent]),
        service_commands(ai),
        utility_commands(ai[:agent], root, infra[:cache]),
        control_commands(ai[:standing], ai[:soul]),
        "help" => ->(_ctx) {
          "just talk. intent is inferred automatically.\n" \
          "exit with /exit or ctrl-C twice."
        }
      )
    end

    def session_commands(infra)
      session = infra[:session]
      undo = infra[:undo]
      logging = infra[:logging]
      config = infra[:config]
      {
        "clear"  => ->(_ctx) { session.clear!; "context cleared" },
        "save"   => ->(_ctx) { session.save!; "session saved" },
        "tokens" => ->(_ctx) { "~#{session.token_est} tokens" },
        "undo"   => ->(_ctx) { result = undo.undo!; result.ok? ? "reverted: #{result.value!}" : result.message },
        "dmesg"  => ->(_ctx) { logging.dmesg },
        "cost"   => ->(_ctx) { "$#{"%.4f" % session.cost}" },
        "config" => ->(_ctx) { config.data.inspect }
      }
    end

    def mode_commands(config)
      {
        "mode" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if Reasoning::Modes::SUPPORTED.include?(arg)
            config["reasoning_mode"] = arg
            config.save!
            "mode: #{arg}"
          else
            "mode: #{config.reasoning_mode} (supported: #{Reasoning::Modes::SUPPORTED.join(", ")})"
          end
        },
        "task" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.empty?
            "task_type: #{config.task_type}"
          else
            config["task_type"] = arg
            config.save!
            "task_type: #{arg}"
          end
        },
        "autotest" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "on"  then config["auto_testing"] = true; config.save!; "autotest: on"
          when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
          else "autotest: #{config.auto_testing? ? "on" : "off"}"
          end
        },
        "persona" => ->(ctx) {
          arg = ctx[:args].to_s.strip.to_sym
          names = Personality::PERSONAS.keys
          if names.include?(arg)
            config["persona"] = arg.to_s
            config.save!
            "persona: #{arg}"
          else
            "persona: #{config["persona"] || "dark_malay"} -- available: #{names.join(", ")}"
          end
        }
      }
    end

    def agent_commands(ai:, root:, infra:)
      agent = ai[:agent]
      scanner = ai[:scanner]
      config = infra[:config]
      bus = infra[:bus]
      metrics = infra[:metrics]
      deliberation = ai[:deliberation]
      council_stage = ai[:council_stage]
      swarm = ai[:swarm]
      {
        "council" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then council_stage.enable!; "council: enabled"
          when "off" then council_stage.disable!; "council: disabled"
          else "council: #{council_stage.enabled? ? "on" : "off"}"
          end
        },
        "swarm" => ->(ctx) {
          args = ctx[:args].to_s.strip.split(" ", 2)
          role = args[0]&.to_sym
          task = args[1].to_s
          if role.nil? || task.empty?
            "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}"
          else
            result = swarm.dispatch(role, task:, context_slice: {})
            result.ok? ? result.value!.inspect : result.message
          end
        },
        "explain" => ->(_ctx) {
          map = Introspection::SelfMap.new(root:)
          info = map.describe
          coverage = map.axiom_coverage
          cov_lines = coverage.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
          stages = "Intake->Infer->Route->Guard->Execute->Council->Lint->Prune->Memo->Render"
          "MASTER -- #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov_lines}"
        },
        "autoloop" => ->(ctx) {
          max = ctx[:args].to_s.strip.to_i
          max = AutoLoop::MAX_CYCLES if max <= 0
          looper = AutoLoop.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
          log = []
          result = looper.run(max_cycles: max) { |cycle, violations|
            log << "  cycle #{cycle}: #{violations.size} violation(s)"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "sweep" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          target = arg.empty? ? root : File.expand_path(arg, root)
          sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
          log = []
          result = sweeper.run(target) { |cycle, file, delta|
            log << "  cycle #{cycle}  #{file}  +#{delta}"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "model" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "list"
            yml_path = File.join(root, "data", "models.yml")
            if File.exist?(yml_path)
              data = Master.load_yaml(yml_path)
              tiers = data["models"] || {}
              model_lines = tiers.flat_map { |tier, ms|
                ms.to_a.map { |mod| "  [#{tier}] #{mod["id"]}" }
              }
              quality_lines = metrics&.model_quality&.map { |mod, stat|
                "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
              } || []
              sections = ["available models:"] + model_lines
              sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
              sections.join("\n")
            else
              "model: #{agent.model}"
            end
          elsif arg.empty?
            "model: #{agent.model}"
          else
            agent.model = arg
            config.save!
            "model: #{arg}"
          end
        },
        "why" => ->(ctx) {
          rule = ctx[:args].to_s.strip
          if rule.empty?
            "usage: /why <rule_name>"
          else
            prompt = "Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                     "give a before/after Ruby example, and state why it matters."
            agent.ask_once(prompt)
          end
        },
        "scan" => ->(ctx) {
          depth = ctx[:args].to_s.include?("deep") ? :deep : :standard
          target = File.join(root, "lib")
          result = scanner.scan_dir(target, depth:)
          next "scan failed" unless result.ok?
          by_rule = Hash.new { |h, k| h[k] = [] }
          result.value!.each do |_file, file_result|
            next unless file_result.ok?
            file_result.value!.each { |v| by_rule[v[:rule].to_s] << v }
          end
          total = by_rule.values.sum(&:size)
          next "clean -- no violations" if total.zero?
          lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
            ["[#{rule}] #{vs.size}"] +
              vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, VIOLATION_TRUNCATE]}" }
          end
          lines << "#{total} total violations"
          lines.join("\n")
        }
      }
    end

    def memory_commands(memory, agent)
      {
        "memory" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.start_with?("forget ")
            key = arg.sub("forget ", "").strip
            memory.forget(key)
            "forgot: #{key}"
          elsif arg.start_with?("remember ")
            parts = arg.sub("remember ", "").split("=", 2)
            key = parts[0].strip
            val = parts[1]&.strip
            val ? (memory.remember(key, val); "remembered: #{key}") : "usage: /memory remember key=value"
          elsif arg.start_with?("search ")
            query = arg.sub("search ", "").strip
            hits = if memory.respond_to?(:semantic_recall)
                     memory.semantic_recall(query)
                   else
                     memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
                   end
            hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
          elsif arg.empty?
            entries = memory.all
            entries.empty? ? "(no memories)" : entries.map { |k, v| "#{k}: #{v}" }.join("\n")
          else
            val = memory.recall(arg)
            val ? "#{arg}: #{val}" : "(not found: #{arg})"
          end
        },
        "dreams" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "consolidate"
            memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
          else
            entries = memory.all
            archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
            active = entries.count { |k, _| !k.to_s.start_with?("archive/") }
            summary = memory.recall("_consolidated_summary")
            lines = ["active: #{active} memories, archived: #{archived}"]
            lines << "last consolidation: #{summary}" if summary
            lines.join("\n")
          end
        }
      }
    end

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
