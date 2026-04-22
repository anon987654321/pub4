begin
  risky_operation
rescue StandardError => e
  logger.error(e.message)
  raise
ensure
  # optional cleanup code
end