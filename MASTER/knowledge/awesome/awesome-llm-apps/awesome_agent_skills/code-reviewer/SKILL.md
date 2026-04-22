# `result` – array of ActiveRecord objects from a previous pipeline stage.
if result.empty?
  logger.warn "User not found; skipping review step"
  return Master::Result::Err.new("User not found")
end

user = result.first
puts "Reviewing #{user.name}"
# Continue with linting, static analysis, etc.
