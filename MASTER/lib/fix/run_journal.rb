# frozen_string_literal: true

# Compatibility entry point. The canonical lifecycle journal lives under
# Fix::Kernel; loading this historical path loads the complete owner and keeps
# the `Master::Fix::RunJournal` constant available to existing callers.
require_relative "kernel"
