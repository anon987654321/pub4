# frozen_string_literal: true

module ChatSseFormatter
  module_function

  def thought_format(event, payload)
    case event
    when "enhance:rewrite"
      "refining your prompt for clarity"
    when "llm:request"
      model = payload[:model].to_s.split("/").last
      model.empty? ? "thinking" : "thinking with #{model}"
    when "llm:escalation"
      "escalating to a deeper model (depth #{payload[:depth]})"
    when "tool:before"
      tool = payload[:tool].to_s.split("::").last.to_s.downcase
      path = payload[:path].to_s
      path.empty? ? "using #{tool}" : "using #{tool} on #{File.basename(path)}"
    when "council_feedback", :council_feedback
      persona = payload[:persona].to_s
      persona.empty? ? "council deliberating" : "#{persona} weighs in"
    when "tribunal:rendered"
      v = payload[:vetoes].to_i.positive? ? "vetoed" : "approved"
      "tribunal #{v}"
    when "pipeline:stage"
      stage = payload[:stage].to_s
      %w[enhance infer route guard execute council deliberate prune memo render].include?(stage) ? "entering #{stage}" : nil
    end
  end

  def dmesg_format(event, payload)
    sub, rest = event.split(":", 2)
    desc = case event
           when "tool:before"
             tool = payload[:tool].to_s.downcase.split("::").last
             path = payload[:path].to_s
             path.empty? ? tool : "#{tool} #{path}"
           when "llm:request"
             model = payload[:model].to_s.split("/").last
             tokens = payload[:tokens]
             tokens ? "→ #{model} (#{tokens} tokens)" : "→ #{model}"
           when "llm:escalation"    then "escalation depth #{payload[:depth]}"
           when "enhance:rewrite"
             o = payload[:original].to_s.length
             e = payload[:enhanced].to_s.length
             "rewrite #{o}→#{e} chars"
           when "pipeline:rollback" then "rollback #{payload[:category]} #{payload[:tag].to_s.split(":").last}"
           when "pipeline:stage"    then "stage #{payload[:stage]} #{payload[:ms]}ms"
           when "fix_loop:pass_start" then "pass #{payload[:pass]}"
           when "fix_loop:clean"      then "clean #{payload[:consecutive_clean]}/2"
           when "fix_loop:plateau"    then "plateau #{payload[:violations]} violations"
           when "fix_loop:ast_fixed"  then "ast #{payload[:transforms]&.join(",")}"
           when "tribunal:rendered"
             v = payload[:vetoes].to_i.positive? ? "veto" : "pass"
             "#{v} #{payload[:judge]}"
           when "backup:ok"         then "synced #{payload[:bytes]}B"
           when "backup:error"      then "error #{payload[:error]}"
           when "scan:complete"     then "#{payload[:count]} violations"
           when "autoloop:cycle"    then "autoloop #{payload[:pass]}/#{payload[:max]}"
           when "pressure:updated"  then "pressure #{payload[:value]}"
           when "cache:hit"         then "cache hit #{payload[:key]}"
           when "cache:miss"        then "cache miss #{payload[:key]}"
           else
             rest&.tr("_", " ") || sub
           end
    return nil if desc.nil?
    "#{sub}0 at master0: #{desc}"
  end
end