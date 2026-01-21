# Update to ensure PLEDGE_AVAILABLE block only applies after first run

# Check if the convergence installer has been run before
if File.exist?(File.expand_path('~/.convergence_installed'))
  # Apply pledge after first run
  if defined?(Pledge)
    Pledge::start
  end
else
  # Allow gem installation without pledge blocking
end