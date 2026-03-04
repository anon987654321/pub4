# frozen_string_literal: true

module CommandRegistry
  SELF_APPLY_MASTER = "MASTER2"

  USAGE_PREFIXES = {
    indent_2: '",   usage: "',
    indent_6: '",          usage: "',
    indent_16: '",                usage: "',
    indent_20: '",                    usage: "',
    indent_21: '",                     usage: "',
    indent_22: '",                      usage: "',
    indent_23: '",                       usage: "',
    indent_25: '",                        usage: "',
    indent_19: '",                   usage: "',
    indent_15: '",               usage: "'
  }.freeze

  DESC_HASH_PREFIX = '":   { desc: "'
  MULTILINE_BREAK = "\",\n      \""

  module_function

  def to_tool_classes(commands:, current_user: nil)
    command_rows = normalize_command_rows(commands)
    tool_names = command_rows.map { |row| row[:tool_name] }.compact.uniq
    tool_records = preload_tools(tool_names, current_user)

    command_rows.map do |row|
      tool = tool_records[row[:tool_name]]
      build_tool_class(row, tool)
    end.compact
  end

  def normalize_command_rows(commands)
    case commands
    when ActiveRecord::Relation
      normalize_relation(commands)
    when Array
      commands.map { |c| normalize_object_or_hash(c) }.compact
    else
      []
    end
  end
  private_class_method :normalize_command_rows

  def normalize_relation(relation)
    rel = relation
          .includes(:tool)
          .references(:tool)

    if rel.column_names.include?("tool_name")
      rel.pluck(:name, :description, :usage, :tool_name).map do |name, description, usage, tool_name|
        { name:, description:, usage:, tool_name: }
      end
    else
      rel.joins(:tool).pluck(:name, :description, :usage, "tools.name").map do |name, description, usage, tool_name|
        { name:, description:, usage:, tool_name: }
      end
    end
  end
  private_class_method :normalize_relation

  def normalize_object_or_hash(obj)
    return normalize_hash(obj) if obj.is_a?(Hash)

    {
      name: obj.respond_to?(:name) ? obj.name : nil,
      description: obj.respond_to?(:description) ? obj.description : nil,
      usage: obj.respond_to?(:usage) ? obj.usage : nil,
      tool_name: tool_name_for(obj)
    }.compact
  end
  private_class_method :normalize_object_or_hash

  def normalize_hash(hash)
    {
      name: hash.fetch(:name, nil),
      description: hash.fetch(:description, nil),
      usage: hash.fetch(:usage, nil),
      tool_name: hash.fetch(:tool_name, nil)
    }.compact
  end
  private_class_method :normalize_hash

  def tool_name_for(obj)
    return obj.tool_name if obj.respond_to?(:tool_name)

    if obj.respond_to?(:tool) && obj.tool
      obj.tool.respond_to?(:name) ? obj.tool.name : nil
    end
  end
  private_class_method :tool_name_for

  def preload_tools(tool_names, current_user)
    return {} if tool_names.empty?

    scope = Tool.where(name: tool_names).includes(:owner)

    if current_user
      scope = scope.where(owner_id: current_user.id) if scope.column_names.include?("owner_id")
    end

    scope.index_by(&:name)
  end
  private_class_method :preload_tools

  def build_tool_class(row, tool)
    name = row.fetch(:name, nil)
    return nil if name.nil? || name.to_s.strip.empty?

    description = row.fetch(:description, "")
    usage = row.fetch(:usage, "")

    ToolClass.new(
      name:,
      description:,
      usage:,
      tool:,
      self_apply_master: SELF_APPLY_MASTER
    )
  end
  private_class_method :build_tool_class

  # Explicit class; avoids banned metaprogramming (define_method)
  class ToolClass
    attr_reader :name, :description, :usage, :tool, :self_apply_master

    def initialize(name:, description:, usage:, tool:, self_apply_master:)
      @name = name
      @description = description
      @usage = usage
      @tool = tool
      @self_apply_master = self_apply_master
    end

    def to_h
      {
        name:,
        description:,
        usage:,
        tool_name: tool&.name,
        self_apply_master:
      }
    end

    def usage_line(indent_key: :indent_6)
      prefix = USAGE_PREFIXES.fetch(indent_key, USAGE_PREFIXES.fetch(:indent_6))
      "#{name}#{prefix}#{usage}\""
    end

    def desc_hash_line
      "#{name}#{DESC_HASH_PREFIX}#{description}\" }"
    end

    def multiline_break
      MULTILINE_BREAK
    end
  end
end