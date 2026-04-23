# frozen_string_literal: true
# Task #13: Parallelize swarm worker dispatch
# Task #15: Confidence-based dynamic model escalation

PATH = "/home/dev/pub4/MASTER/lib/master/autoloop.rb"
src  = File.read(PATH, encoding: "UTF-8")

# ── Task #13: parallel batch dispatch ────────────────────────────────────────

old_dispatch = \
"        violations.first(BATCH_SIZE).each_with_index do |v, idx|\n" \
"          sleep RATE_LIMIT_SLEEP unless idx.zero? # Pace for free-tier stability\n" \
"          fix = request_fix(v)\n" \
"          apply_fix(v[:file], fix) if fix\n" \
"        end"

new_dispatch = \
"        # Deduplicate by file — one fix per unique file to avoid write-race.\n" \
"        by_file = violations.first(BATCH_SIZE * 2).uniq { |v| v[:file] }.first(BATCH_SIZE)\n" \
"\n" \
"        mutex   = Mutex.new\n" \
"        fixes   = {}\n" \
"        stagger = RATE_LIMIT_SLEEP.to_f / BATCH_SIZE  # 5 s apart — stays within free-tier quota\n" \
"\n" \
"        threads = by_file.each_with_index.map do |v, idx|\n" \
"          sleep(stagger * idx) if idx.positive?\n" \
"          Thread.new do\n" \
"            fix = request_fix(v)\n" \
"            mutex.synchronize { fixes[v[:file]] = [v, fix] } if fix\n" \
"          end\n" \
"        end\n" \
"        threads.each(&:join)\n" \
"\n" \
"        fixes.each_value { |v, fix| apply_fix(v[:file], fix) }"

abort "dispatch anchor not found" unless src.include?(old_dispatch)
src.sub!(old_dispatch, new_dispatch)

# ── Task #15: confidence score + escalation retry ────────────────────────────

# 1. Add CONFIDENCE_THRESHOLD constant after MIN_SIZE_RATIO
old_const = "    MIN_SIZE_RATIO   = 0.80   # Reject fix if output < 80% of original file size"
new_const  = \
"    MIN_SIZE_RATIO       = 0.80   # Reject fix if output < 80% of original file size\n" \
"    CONFIDENCE_THRESHOLD = 0.60   # Below this, escalate to a reflective retry"

abort "const anchor not found" unless src.include?(old_const)
src.sub!(old_const, new_const)

# 2. In request_fix, after extract_code, add confidence check before return
old_extract = \
"          prompt = attempt.zero? ? base_prompt : reflected_prompt(base_prompt, last_error, attempt)\n" \
"          return extract_code(@agent.ask(prompt).to_s)"

new_extract = \
"          prompt = attempt.zero? ? base_prompt : reflected_prompt(base_prompt, last_error, attempt)\n" \
"          fix    = extract_code(@agent.ask(prompt).to_s)\n" \
"          if fix && confidence_score(fix, src) < CONFIDENCE_THRESHOLD && attempt < MAX_FIX_RETRIES - 1\n" \
"            @bus&.publish(\"autoloop:escalate\", file: violation[:file], attempt: attempt + 1)\n" \
"            last_error = 'low confidence'\n" \
"            next\n" \
"          end\n" \
"          return fix"

abort "extract anchor not found" unless src.include?(old_extract)
src.sub!(old_extract, new_extract)

# 3. Add `confidence_score` private method before `syntax_ok?`
old_syntax_method = "    def syntax_ok?(content)"
new_methods = \
"    # Returns 0.0-1.0. Signals how structurally complete the LLM output is.\n" \
"    # Low score triggers escalation retry with a reflective prompt (Task #15).\n" \
"    def confidence_score(code, original_src)\n" \
"      return 0.0 if code.nil? || code.strip.empty?\n" \
"\n" \
"      score = 0.0\n" \
"      score += 0.25 if code.include?(\"# frozen_string_literal: true\")\n" \
"      score += 0.25 if code.match?(/\\A.*?(?:module |class )[A-Z]/m)\n" \
"      ratio  = code.bytesize.to_f / [original_src.bytesize, 1].max\n" \
"      score += 0.25 if ratio >= MIN_SIZE_RATIO && ratio <= 2.0\n" \
"      score += 0.25 if syntax_ok?(code)\n" \
"      score\n" \
"    end\n" \
"\n" \
"    def syntax_ok?(content)"

abort "syntax_ok anchor not found" unless src.include?(old_syntax_method)
src.sub!(old_syntax_method, new_methods)

File.write(PATH, src)
puts "autoloop.rb patched"

ok = system("ruby -c #{PATH} > /dev/null 2>&1")
puts ok ? "syntax ok" : "SYNTAX ERROR"
