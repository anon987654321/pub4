#!/usr/bin/env sh
# Optional Claude Code / OpenCode lifecycle adapter for Dilla's synthetic cue renderer.
# Accepts either an explicit allowlisted Dilla event or the JSON lifecycle payload
# supplied on stdin by Claude Code. Unsupported events are a quiet no-op.
set -eu

event=${1:-}
if [ -z "$event" ]; then
  # Parse only the lifecycle event name; never persist or print the hook payload.
  event=$(ruby -rjson -e '
    map = {
      "SessionStart" => "start",
      "UserPromptSubmit" => "submit",
      "Stop" => "complete",
      "StopFailure" => "error",
      "PostToolUseFailure" => "error",
      "Notification" => "notification",
      "PreCompact" => "precompact",
      "SessionEnd" => "session_end",
      "session.created" => "start",
      "session.idle" => "complete",
      "session.error" => "error",
      "session.compacted" => "precompact",
      "session.deleted" => "session_end"
    }
    begin
      payload = JSON.parse(STDIN.read)
      event_object = payload["event"]
      candidates = [
        payload["hook_event_name"],
        event_object.is_a?(Hash) ? event_object["type"] : event_object,
        payload["type"]
      ]
      cue = candidates.compact.lazy.map { |name| map[name.to_s] }.find { |value| value }
      print cue if cue
    rescue JSON::ParserError, TypeError
      # Malformed/unsupported input should never interrupt a host CLI.
    end
  ' 2>/dev/null || true)
fi

case "$event" in
  start|submit|complete|error|notification|precompact|session_end) ;;
  *) exit 0 ;;
esac

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec ruby "$script_dir/dilla.rb" sound-fx "$event" --play
