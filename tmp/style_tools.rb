# frozen_string_literal: true

# Add doc comments to tool files that lack them

base = "/home/dev/pub4/MASTER/lib/master/tools"

comments = {
  "ask_llm.rb"         => "# AskLlm — delegate sub-questions to the LLM agent mid-pipeline.",
  "batch_replace.rb"   => "# BatchReplace — apply multiple search-and-replace operations in one pass.",
  "clean.rb"           => "# Clean — run linters and auto-formatters on project files.",
  "list_dir.rb"        => "# ListDir — list directory contents with filtering and depth control.",
  "read_file.rb"       => "# ReadFile — read file contents with line-range support and undo tracking.",
  "search_files.rb"    => "# SearchFiles — regex search across project files with context lines.",
  "shell.rb"           => "# Shell — execute shell commands with timeout and governor approval.",
  "str_replace.rb"     => "# StrReplace — surgical string replacement in files with undo support.",
  "tree.rb"            => "# Tree — show project directory structure as an indented tree.",
  "web_search.rb"      => "# WebSearch — query external search APIs with governor rate limiting.",
  "write_file.rb"      => "# WriteFile — create or overwrite files with TextHygiene normalization.",
  "llm.rb"             => "# LLM — shared base module for LLM-backed tool functionality.",
  "path_guard.rb"      => "# PathGuard — enforce path safety: block traversal, symlinks, sensitive files.",
  "search_knowledge.rb" => nil,  # already has comment
  "symbol_lookup.rb"   => nil,   # already has comment
  "ast_edit.rb"        => nil,   # already has comment
  "git_context.rb"     => nil    # already has comment
}

comments.each do |file, comment|
  next unless comment
  path = File.join(base, file)
  next unless File.exist?(path)

  src = File.read(path, encoding: "UTF-8")
  # Insert comment before the class/module line that lacks one
  # Find the class line and check if previous line is already a comment
  lines = src.lines
  inserted = false
  lines.each_with_index do |line, i|
    if line =~ /^\s*class\s+\w/ && i > 0 && !lines[i - 1].strip.start_with?("#")
      lines.insert(i, "    #{comment}\n")
      inserted = true
      break
    end
  end

  if inserted
    File.write(path, lines.join)
    puts "patched: #{file}"
  else
    puts "skipped: #{file} (already has comment or no class line)"
  end
end
