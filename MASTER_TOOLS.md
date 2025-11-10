# Master Configuration & Import System

A comprehensive configuration-driven code management system for consolidating and maintaining code across multiple repositories.

## Overview

This system provides three main components:

1. **master.json** - Single source of truth for all configuration
2. **bin/master.rb** - Terminal UI for code formatting, auditing, and prompt management
3. **lib/importer.rb** - GitHub API-based code importer

## Master.json Configuration

The `master.json` file consolidates all configuration including:

- **meta**: Version, owner, LLM configurations
- **secrets**: Environment variable requirements
- **runtime**: Shell, platform, VPS, and domain configurations
- **code_quality**: Principles, enforcement rules, forbidden patterns
- **policy**: Formatting rules (ternary, line length, spacing scale, deduplication)
- **tools**: File extensions and external tools per language
- **design_system**: Typography, gestalt principles, components, accessibility, WCAG contrast
- **prompts**: Reusable prompt templates for refactoring, security, performance, etc.
- **imports**: Configuration for importing code from other repositories

### Key Sections

#### Policy
```json
"policy": {
  "forbid_ternary": true,
  "max_line_length": 120,
  "spacing_scale": [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64],
  "dedup_threshold": 3
}
```

#### Tools
```json
"tools": {
  "file_extensions": ["rb", "sh", "zsh", "html", "js", "css", "scss", "json", "md"],
  "external_tools": {
    "rb": "rubocop -a",
    "js": "prettier --write",
    "py": "black"
  }
}
```

#### Imports
```json
"imports": {
  "owner": "anon987654321",
  "repos": ["pub", "pub2", "pub3", "railsy"],
  "branch": "main",
  "include_extensions": ["rb", "sh", "zsh", "html", "js", "css"],
  "exclude_paths": ["vendor/", "node_modules/", "tmp/", ".git/"],
  "dest_dir": "imports"
}
```

## bin/master.rb - Code Formatter & Auditor

Terminal UI for code formatting, auditing, and prompt management.

### Usage

```bash
ruby bin/master.rb
# or
./bin/master.rb
```

### Features

#### 1. Format
Automatically transforms code according to configured rules:

- **Simplify negations**: Converts `if !condition` to `unless condition`
- **Deduplicate lines**: Removes duplicate non-comment lines appearing more than 3 times
- **Normalize spacing**: Rounds CSS/SCSS spacing values to nearest spacing scale value
- **External tools**: Optionally runs external formatters (rubocop, prettier, black, etc.)

#### 2. Audit
Checks code for policy violations:

- **Ternary operators**: Flags forbidden ternary usage (`? :`)
- **Line length**: Detects lines exceeding max_line_length (default 120)
- **WCAG contrast**: Notes files with color definitions for manual contrast checking

#### 3. Prompts
View and export the prompt library defined in master.json:

- Refactoring prompts
- Security audit prompts
- Performance optimization prompts
- Accessibility compliance prompts
- Zsh best practices prompts

#### 4. Export
Exports all prompts to a timestamped text file for use with LLMs or documentation.

### Examples

**Transform Ruby code:**
```ruby
# Before
if !user.admin?
  deny_access
end

# After (automatically transformed)
unless user.admin?
  deny_access
end
```

**Normalize CSS spacing:**
```css
/* Before */
.container {
  padding: 15px;
  margin: 23px;
  gap: 10px;
}

/* After (normalized to spacing scale) */
.container {
  padding: 16px;
  margin: 24px;
  gap: 8px;
}
```

## lib/importer.rb - GitHub Code Importer

Imports code from multiple GitHub repositories using the GitHub API (stdlib only, no external gems).

### Usage

```bash
ruby lib/importer.rb [config_path]
# or
./lib/importer.rb
```

Default config path is `master.json`.

### Features

- Uses GitHub Git Trees API with `recursive=1` for efficient file listing
- Filters files by extension (include_extensions)
- Excludes unwanted paths (vendor, node_modules, tmp, .git)
- Downloads blob content via `/git/blobs/:sha`
- Base64 decodes content automatically
- Organizes imports by repository: `imports/repo_name/path/to/file`
- Handles rate limiting with automatic retry
- Optional authentication via `GITHUB_TOKEN` environment variable

### Authentication (Optional)

For private repositories or higher rate limits:

```bash
export GITHUB_TOKEN=your_github_token
ruby lib/importer.rb
```

### Output Structure

```
imports/
├── pub/
│   ├── lib/
│   │   └── example.rb
│   └── config/
│       └── settings.json
├── pub2/
│   └── scripts/
│       └── deploy.sh
├── pub3/
│   └── ...
└── railsy/
    └── ...
```

## Configuration-Driven Design

All behavior is controlled through master.json:

- **No hard-coded constants** in Ruby code
- **cfg() helper** for nested config access
- **Easy customization** by editing JSON
- **Single source of truth** for all rules

## File Processing

Both bin/master.rb and lib/importer.rb automatically:

- Process files matching configured extensions
- Skip vendor/, node_modules/, tmp/, .git/ directories
- Handle errors gracefully with informative messages
- Provide progress indicators

## Requirements

- Ruby 2.7+ (tested with Ruby 3.2.3)
- No external gems required (uses stdlib only: json, fileutils, net/http, uri, base64)
- Optional: external tools (rubocop, prettier, black) for enhanced formatting

## Architecture

### CodeTransformer Module
- `transform(content, ext)` - Apply formatting transformations
- `simplify_negations(content)` - Convert if ! to unless
- `deduplicate_lines(content)` - Remove duplicate lines
- `normalize_spacing(content)` - Round spacing to scale
- `audit(content, filepath)` - Check for violations

### MasterFormatter Class
- Terminal UI with menu system
- File discovery with filtering
- Format/Audit operations
- Prompt management
- External tool integration

### Importer Class
- GitHub API client (stdlib only)
- Tree-based file discovery
- Blob content download
- Base64 decoding
- Rate limit handling
- Authentication support

## Development

### Testing

Run the test suite:

```bash
# Test CodeTransformer
ruby test_files/test_runner.rb

# Test Importer configuration
ruby test_files/test_importer.rb
```

### Extending

To add new transformations:

1. Add rules to `policy` section in master.json
2. Implement transformation in `CodeTransformer` module
3. Add audit checks as needed

To add new external tools:

1. Update `tools.external_tools` in master.json
2. Ensure tool is available in PATH

## License

See repository license.
