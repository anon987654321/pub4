# MASTER Snapshot — lib/master/command_registry/
Generated: 2026-05-04T10:21:42Z

## lib/master/command_registry/agent_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def agent_commands(ai:, root:, infra:)
      scan_loop_commands(ai:, root:, infra:)
        .merge(model_agent_commands(ai:, root:, infra:))
        .merge(crit_command(ai:, root:))
        .merge(ideate_command(ai:))
        .merge(topic_command(infra:))
    end

    def scan_loop_commands(ai:, root:, infra:)
      agent = ai[:agent]
      scanner = ai[:scanner]
      bus = infra[:bus]
      deliberation = ai[:deliberation]
      autoloop = ai[:autoloop]
      {
        "autoloop" => ->(ctx) {
          max = ctx[:args].to_s.strip.to_i
          max = AutoLoop::MAX_CYCLES if max <= 0
          log = []
          result = autoloop.run(max_cycles: max) { |cycle, violations|
            log << "  cycle #{cycle}: #{violations.size} violation(s)"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "sweep" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          target = arg.empty? ? root : File.expand_path(arg, root)
          sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus, code_index: infra[:code_index])
          log = []
          result = sweeper.run(target) { |cycle, file, delta|
            log << "  cycle #{cycle}  #{file}  +#{delta}"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "scan" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          profile, depth, rule_filter = resolve_scan_profile(arg, root)
          raw_arg = arg.sub(/\A(?:deep|quick|full|critical|solid|axioms)\s*/, "").strip
          target_arg = raw_arg.empty? ? nil : File.expand_path(raw_arg)
          pairs = if target_arg && File.file?(target_arg)
            fr = scanner.scan(target_arg, depth:)
            [[target_arg, fr]]
          elsif target_arg && File.directory?(target_arg)
            dir_result = scanner.scan_dir(target_arg, depth:, glob: "**/*")
            next "scan failed" unless dir_result.ok?
            dir_result.value!
          else
            dir_result = scanner.scan_dir(File.join(root, "lib"), depth:)
            next "scan failed" unless dir_result.ok?
            dir_result.value!
          end
          by_rule = Hash.new { |h, k| h[k] = [] }
          pairs.each do |_file, file_result|
            next unless file_result.respond_to?(:ok?) && file_result.ok?
            file_result.value!.each do |v|
              next if rule_filter && !rule_filter.include?(v[:rule].to_s)
              by_rule[v[:rule].to_s] << v
            end
          end
          total = by_rule.values.sum(&:size)
          header = profile ? "[profile: #{profile}] " : ""
          next "#{header}clean -- no violations" if total.zero?
          lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
            ["[#{rule}] #{vs.size}"] +
              vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, VIOLATION_TRUNCATE]}" }
          end
          lines << "#{header}#{total} total violations"
          lines.join("\n")
        }
      }
    end

    def resolve_scan_profile(arg, root)
      profiles_cfg = begin
        data = Master.load_yaml(File.join(root, "data", "workflow.yml"))
        groups  = data.dig("principle_groups") || {}
        profiles = data.dig("scan_profiles") || {}
        [groups, profiles]
      rescue StandardError => _e
        [{}, {}]
      end
      groups, profiles = profiles_cfg

      profile_name = %w[quick full critical solid axioms].find { |p| arg.start_with?(p) }
      profile_name ||= "deep" if arg.start_with?("deep")

      if profile_name && profile_name != "deep"
        cfg   = profiles[profile_name] || {}
        depth = (cfg["depth"] == "deep") ? :deep : :standard
        rule_ids = groups[cfg["rules"].to_s]
        rule_filter = (rule_ids && cfg["rules"] != "*") ? rule_ids.map(&:to_s).to_set : nil
        [profile_name, depth, rule_filter]
      elsif profile_name == "deep"
        [nil, :deep, nil]
      else
        [nil, :standard, nil]
      end
    end

    def model_agent_commands(ai:, root:, infra:)
      council_meta_commands(ai:, root:).merge(model_commands(ai:, root:, infra:))
    end

    def council_meta_commands(ai:, root:)
      council_stage = ai[:council_stage]
      swarm         = ai[:swarm]
      {
        "council" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then council_stage.enable!; "council: enabled"
          when "off" then council_stage.disable!; "council: disabled"
          else "council: #{council_stage.enabled? ? "on" : "off"}"
          end
        },
        "swarm"   => ->(ctx) { dispatch_swarm(swarm, ctx[:args].to_s.strip) },
        "explain" => ->(_ctx) { explain_master(root) }
      }
    end

    def dispatch_swarm(swarm, arg)
      parts = arg.split(" ", 2)
      role  = parts[0]&.to_sym
      task  = parts[1].to_s
      return "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}" if role.nil? || task.empty?
      result = swarm.dispatch(role, task:, context_slice: {})
      result.ok? ? result.value!.inspect : result.message
    end

    def explain_master(root)
      map    = Introspection::SelfMap.new(root:)
      info   = map.describe
      cov    = map.axiom_coverage.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
      stages = "Intake->Infer->Route->Guard->Execute->Council->Lint->Prune->Memo->Render"
      "MASTER -- #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov}"
    end

    def model_commands(ai:, root:, infra:)
      agent   = ai[:agent]
      config  = infra[:config]
      metrics = infra[:metrics]
      {
        "model" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next list_models(root, metrics, agent) if arg == "list"
          next "model: #{agent.model}" if arg.empty?
          agent.model = arg; config.save!; "model: #{arg}"
        },
        "why" => ->(ctx) {
          rule = ctx[:args].to_s.strip
          next "usage: /why <rule_name>" if rule.empty?
          agent.ask_once("Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                         "give a before/after Ruby example, and state why it matters.")
        }
      }
    end

    def list_models(root, metrics, agent)
      yml_path = File.join(root, "data", "models.yml")
      return "model: #{agent.model}" unless File.exist?(yml_path)
      data = Master.load_yaml(yml_path)
      tiers = data["models"] || {}
      model_lines = tiers.flat_map { |tier, ms| ms.to_a.map { |mod| "  [#{tier}] #{mod["id"]}" } }
      quality_lines = metrics&.model_quality&.map { |mod, stat|
        "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
      } || []
      sections = ["available models:"] + model_lines
      sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
      sections.join("\n")
    end

    def crit_command(ai:, root:)
      deliberation = ai[:deliberation]
      {
        "crit" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next "usage: /crit <file|text>" if arg.empty?
          payload = if File.exist?(File.expand_path(arg, root))
            File.read(File.expand_path(arg, root), encoding: "UTF-8")
          else
            arg
          end
          result = deliberation.review(payload, context: "explicit /crit session")
          next result.message if result.err?
          format_crit_feedback(result.value!)
        }
      }
    end

    def format_crit_feedback(feedback)
      feedback.map { |f|
        veto = f[:veto_role] ? " [VETO ELIGIBLE]" : ""
        "#{f[:persona]} (#{f[:role]})#{veto}:\n#{f[:feedback].to_s.strip}"
      }.join("\n\n---\n\n")
    end

    def topic_command(infra:)
      session = infra[:session]
      {
        "topic" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.empty?
            current_topic = session.respond_to?(:topic) ? session.topic : nil
            current_topic ? "topic: #{current_topic}" : "no topic set  /topic <description>"
          else
            session.topic = arg if session.respond_to?(:topic=)
            "topic: #{arg}"
          end
        }
      }
    end

    def ideate_command(ai:)
      ideation = ai[:ideation]
      {
        "ideate" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next "usage: /ideate <prompt> [-- constraint1, constraint2]" if arg.empty?
          prompt, constraints_raw = arg.split(" -- ", 2)
          constraints = constraints_raw ? constraints_raw.split(",").map(&:strip).reject(&:empty?) : []
          result = ideation.ideate(prompt.strip, constraints:)
          next result.message if result.err?
          v = result.value!
          lines = []
          lines << "ideas (#{v[:ideas].size}):"
          v[:ideas].each { |i| lines << "  - #{i}" }
          lines << ""
          v[:critiques].each_with_index { |c, n| lines << "critique #{n + 1}: #{c}" }
          lines << ""
          lines << "synthesis:"
          lines << v[:final]
          lines.join("\n")
        }
      }
    end
  end
end

```

## lib/master/command_registry/memory_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def memory_commands(memory, agent)
      {
        "memory" => ->(ctx) { dispatch_memory(memory, ctx[:args].to_s.strip) },
        "dreams" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "consolidate"
            memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
          else
            entries  = memory.all
            archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
            active   = entries.count { |k, _| !k.to_s.start_with?("archive/") }
            summary  = memory.recall("_consolidated_summary")
            lines    = ["active: #{active} memories, archived: #{archived}"]
            lines << "last consolidation: #{summary}" if summary
            lines.join("\n")
          end
        }
      }
    end

    def dispatch_memory(memory, arg)
      case arg
      when /\Aforget (.+)/  then memory.forget($1.strip); "forgot: #{$1.strip}"
      when /\Aremember (.+)/
        key, value = $1.split("=", 2).map(&:strip)
        value ? (memory.remember(key, value); "remembered: #{key}") : "usage: /memory remember key=value"
      when /\Asearch (.+)/ then memory_search(memory, $1.strip)
      when ""
        (e = memory.all).empty? ? "(no memories)" : e.map { |k, v| "#{k}: #{v}" }.join("\n")
      else
        (r = memory.recall(arg)) ? "#{arg}: #{r}" : "(not found: #{arg})"
      end
    end

    def memory_search(memory, query)
      hits = memory.respond_to?(:semantic_recall) ? memory.semantic_recall(query) :
               memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
      hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
    end
  end
end

```

## lib/master/command_registry/service_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    BINARY_SNIFF_BYTES = 512

    module_function

    def control_commands(standing, soul)
      {
        "orders" => ->(ctx) { dispatch_orders(standing, ctx[:args].to_s.strip) },
        "soul"   => ->(ctx) { dispatch_soul(soul, ctx[:args].to_s.strip) }
      }
    end

    def service_commands(ai, phase_gates = nil)
      heartbeat = ai[:heartbeat]
      skills    = ai[:skills]
      {
        "heartbeat" => ->(ctx) { dispatch_heartbeat(heartbeat, ctx[:args].to_s.strip) },
        "skills"    => ->(ctx) {
          arg   = ctx[:args].to_s.strip
          found = skills&.find(arg)
          arg.empty? ? (skills&.list || "(no skills)") : (found ? "#{found[:name]}: #{found[:description]}" : "(not found: #{arg})")
        },
        "phase" => ->(ctx) { dispatch_phase(phase_gates, ctx[:args].to_s.strip) }
      }
    end

    def dispatch_phase(gates, arg)
      return "no phase_gates configured" unless gates
      case arg
      when "", "status" then gates.status
      when "advance"    then result = gates.advance!; result.ok? ? result.value! : result.message
      when /\Aforce (.+)\z/  then gates.force!($1.strip).value!
      when /\Ameet (.+)\z/   then gates.meet_gate!($1.strip); "gate met: #{$1.strip}"
      else "phase: #{gates.current}  /phase [status|advance|force <name>|meet <gate>]"
      end
    end

    def dispatch_orders(standing, arg)
      case arg
      when "list", "" then standing.list
      when /\Aenable (.+)\z/  then standing.enable($1.strip)
      when /\Adisable (.+)\z/ then standing.disable($1.strip)
      when /\Aadd name=(\S+) cmd=(.+)\z/ then standing.upsert(name: $1, command: $2.strip)
      when "run"
        results = standing.run_due!
        results.empty? ? "no orders due" :
          results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
      when /\Areset (.+)\z/ then standing.reset($1.strip)
      else "usage: /orders  /orders enable|disable|reset <name>  /orders run"
      end
    end

    def dispatch_soul(soul, arg)
      case arg
      when "", "show"          then soul.summary
      when "version", "changelog" then soul.changelog
      when "diff"              then soul.diff
      when "approve"           then soul.approve
      when "reject"            then soul.reject
      when "rollback"          then soul.rollback
      when /\Apropose (.+)\z/  then soul.propose($1.strip)
      else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
      end
    end

    def dispatch_heartbeat(heartbeat, arg)
      case arg
      when "run"   then heartbeat ? heartbeat.run_due!.map { |r| "#{r[:name]}: #{r[:result]}" }.join("\n") : "no heartbeat"
      when "start" then heartbeat&.start!; "heartbeat started"
      when "stop"  then heartbeat&.stop!;  "heartbeat stopped"
      else heartbeat&.list || "no heartbeat"
      end
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
                      .reject { |f| begin; File.binread(f, BINARY_SNIFF_BYTES).include?("\x00"); rescue StandardError => _e; true; end }
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
          out, = Open3.capture2e("git", "-C", root, "diff", base, "--stat")
          out.strip.empty? ? "(no changes since #{base})" : out.strip
        },
        "commit" => ->(_ctx) {
          diff, = Open3.capture2e("git", "-C", root, "diff", "--cached", "--stat")
          diff, = Open3.capture2e("git", "-C", root, "diff", "--stat") if diff.strip.empty?
          next "nothing to commit" if diff.strip.empty?
          prompt = "Write a concise git commit message (1 line, imperative mood) for these changes:\n#{diff}"
          msg = agent.ask_once(prompt).strip.lines.first.to_s.strip
          Open3.capture2e("git", "-C", root, "add", "-u")
          out, = Open3.capture2e("git", "-C", root, "commit", "-m", msg)
          out.strip
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

```
