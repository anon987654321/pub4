# frozen_string_literal: true

# Migrated from data/rules.yml UNBOUNDED_RETRY. The migration regressed the
# detector to the bare word — 24 findings on lib/, every one a comment, a
# :retry symbol, a retry? method, a retry: kwarg or a regex literal, while
# the registry twin in universal_rules.rb already carries the narrowed
# keyword. The keyword never follows `:` or a word character, never
# precedes `?`, `:` or a word character, never sits beside `|`; a comment
# only talks about it.
Law.define(:UNBOUNDED_RETRY) do
  source "Release It! — retry budgets / bounded retries (Nygard)"
  severity :error
  detect { |line| (s = line.strip) && !s.start_with?("#") && (s.match?(/(?<![:\w|])retry(?![?:\w|])/) || s.match?(/while\s+true/)) }
  fix "Add max_attempts cap and exponential backoff."
  bad  "retry"
  good <<~X
    next if action == :retry
    def retry?(error, attempt:)
    @bus&.publish("llm:failover_backoff", retry: retry_index + 1)
    [+0.18, :name, /retry|loop|escalat/],
    # a retry then spawned a duplicate on the same output file
    attempts += 1 and redo if attempts < 3
  X
end
