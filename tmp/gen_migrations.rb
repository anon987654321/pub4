#!/usr/bin/env ruby
# parse `bin/rails generate model X foo:bar baz:qux` lines from a setup .sh
# and emit ActiveRecord migrations into <out_root>/db/migrate/.
# usage: ruby gen_migrations.rb <input.sh> <out_root> <ts_base>
require "fileutils"

input, root, ts_base = ARGV
abort "usage: gen_migrations.rb <input.sh> <out_root> <ts_base>" unless input && root && ts_base
ts = ts_base.to_i

src = File.read(input)

# join continuation lines, then pick "rails generate model ..." statements
joined = src.gsub(/\\\n\s*/, " ")
gens = []
joined.each_line do |line|
  next unless line =~ /(?:bin\/)?rails generate model\s+([A-Z]\w+)\s+(.+)$/
  model = $1
  rest  = $2.split(/#/).first.to_s
  gens << [model, rest]
end

def parse_field(tok)
  parts = tok.split(":")
  name  = parts.shift
  type  = parts.shift
  opts  = parts
  refs_to = nil
  if type =~ /\Areferences\{(\w+)\}\z/
    refs_to = $1
    type = "references"
  end
  [name, type, opts, refs_to]
end

def col_line(name, type, opts, refs_to)
  case type
  when "references"
    extra = refs_to ? ", foreign_key: { to_table: :#{refs_to.downcase}s }" : ", foreign_key: true"
    "      t.references :#{name}#{extra}"
  else
    default = opts.find { |o| o.include?("default[") }
    line = "      t.#{type} :#{name}"
    if default
      val = default[/default\[([^\]]+)\]/, 1]
      ruby_val =
        case type
        when "boolean" then (val == "true").to_s
        when "integer" then val
        else "\"#{val}\""
        end
      line += ", default: #{ruby_val}"
    end
    line
  end
end

def index_lines(table, fields)
  out = []
  fields.each do |name, type, opts, _|
    next if type == "references"
    out << "    add_index :#{table}, :#{name}, unique: true" if opts.include?("uniq")
  end
  out
end

written = 0
gens.each do |model, fields_blob|
  toks   = fields_blob.split(/\s+/).reject { |t| t.empty? || t.start_with?("--") }
  fields = toks.map { |t| parse_field(t) }
  snake = model.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
  table = case snake
          when /is\z/            then snake.sub(/is\z/, "es")
          when /[aeiou]y\z/      then "#{snake}s"
          when /y\z/             then snake.sub(/y\z/, "ies")
          when /(s|x|z|ch|sh)\z/ then "#{snake}es"
          else "#{snake}s"
          end
  ts += 1
  filename = "#{ts}_create_#{table}.rb"
  classname = "Create#{table.split("_").map(&:capitalize).join}"

  body = []
  body << "class #{classname} < ActiveRecord::Migration[8.1]"
  body << "  def change"
  body << "    create_table :#{table} do |t|"
  fields.each { |n, ty, op, rt| body << col_line(n, ty, op, rt) }
  body << "      t.timestamps"
  body << "    end"
  index_lines(table, fields).each { |l| body << l }
  body << "  end"
  body << "end"
  body << ""

  out = File.join(root, "db", "migrate", filename)
  FileUtils.mkdir_p(File.dirname(out))
  File.write(out, body.join("\n"))
  puts "wrote #{out}"
  written += 1
end

puts "generated #{written} migrations"
