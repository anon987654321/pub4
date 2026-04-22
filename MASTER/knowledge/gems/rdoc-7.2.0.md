require 'rdoc'

# Initialize RDoc with a fresh options object.
rdoc = RDoc::RDoc.new

# Configure documentation generation.
# Mirrors CLI flags; settings are supplied via a hash for clarity.
rdoc.options = RDoc::Options.new.tap do |opt|
  opt.title     = 'My Project'   # Title displayed in generated docs.
  opt.main      = 'README.md'    # Home page file.
  opt.op_dir    = 'doc/rdoc'     # Output directory.
  opt.generator = 'darkfish'     # Use any installed generator.
  opt.quiet     = true           # Suppress console output.
end

# Generate documentation for the specified paths.
# Accepts glob patterns for files or directories.
rdoc.document(['lib/**/*.rb', 'README.md'])