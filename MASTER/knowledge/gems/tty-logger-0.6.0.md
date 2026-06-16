require "tty/logger"

# Create a logger (auto‑detects STDOUT, uses color when supported)
logger = TTY::Logger.new

# Simple messages
logger.info    "Deployed"
logger.success "Deployed", "successfully"
logger.warn    "Low memory"
logger.error   "Failed"

# Advanced usage – custom output format, timestamps, and metadata
logger = TTY::Logger.new(
  level:   :info,                     # :debug, :info, :warn, :error, :fatal, :unknown
  output:  $stdout,                   # Any IO object, e.g. File.open('log.txt', 'a')
  formatter: :color,                  # :simple, :json, :pretty, :color
  timestamp: true,                    # prepend ISO‑8601 timestamp
  namespace: "my_app",                # prepend namespace to each line
  # Optional: custom colors per level
  colors: {
    info:    :blue,
    success: :green,
    warn:    :yellow,
    error:   :red,
    fatal:   [:red, :bright],
  }
)

# Log with additional data (hash will be pretty‑printed)
logger.info "User signed in", user: "alice", id: 42

# Conditional logging – respects the configured level
logger.debug "Expensive debug info" # ignored unless level <= :debug
