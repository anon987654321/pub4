#!/usr/bin/env ruby
# frozen_string_literal: true

# Does one changed Rails source still compile? Run under brgen's bundle by /fix's repair loop
# (Fix::SourceCompile) once a repair is on disk:
#
#   bundle exec ruby MASTER/tools/rails/compile_check.rb <file> [stylesheet entry ...]

# A view compiles through ActionView's own Erubi, which knows block helpers; stdlib ERB does not.
# A stylesheet is judged by the entries that import it, with the app's and the shared engine's
# stylesheet roots. Exit 0 compiles, 1 names the error, 2 means this file is not one it reads.

# Inside a method, as ActionView compiles every template: a layout's `yield` is valid there.
def view_failure(path)
  require "action_view"

  body = ActionView::Template::Handlers::ERB::Erubi.new(File.read(path, encoding: "UTF-8"), trim: true).src
  RubyVM::InstructionSequence.compile("def _template(local_assigns, output_buffer)\n#{body}\nend", path)
  nil
rescue SyntaxError => e
  "#{File.basename(path)}: does not compile: #{e.message.lines.first(3).join.strip}"
end

def stylesheet_failure(path, entries)
  require "sass-embedded"

  shared = File.expand_path("../__shared/app/assets/stylesheets", Dir.pwd)
  (entries.empty? ? [path] : entries).each do |entry|
    Sass.compile(entry, load_paths: [File.dirname(entry), shared], quiet_deps: true,
                        silence_deprecations: %w[import global-builtin])
  rescue Sass::CompileError => e
    return "#{File.basename(path)}: #{File.basename(entry)} does not compile: #{e.message.lines.first(2).join.strip}"
  end
  nil
end

path = ARGV.fetch(0)
failure =
  case path
  when /\.erb\z/ then view_failure(path)
  when /\.s?css\z/ then stylesheet_failure(path, ARGV.drop(1))
  else exit 2
  end
abort failure if failure
