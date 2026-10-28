# frozen_string_literal: true

# Compatibility entry point. The canonical implementation and identity live
# under Fix::Kernel; the adapter installs the legacy constant before its child
# modules load so every pass module reopens the same class object.
require_relative "kernel"
require_relative "kernel/convergence_adapter"
