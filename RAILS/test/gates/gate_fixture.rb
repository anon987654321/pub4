# frozen_string_literal: true

require "fileutils"

# Pointing a gate at a planted tree.
#
# A gate test that only runs the gate over this repository and asserts "clean"
# proves nothing: it passes just as well against a gate whose body is `return
# ok`. The test has to plant the defect the gate exists to catch, watch it fail,
# remove the defect and watch it pass.
#
# Several source gates make that awkward. They resolve their subject from a
# constant computed at load time — `ROOT = File.expand_path("../../../..",
# __dir__)` and the paths derived from it — and offer no root argument, so the
# only way to run one over a fixture is to rewrite those constants around the
# call. `with_constants` does that and puts them back, so one test cannot change
# what the next one measures. Gates that already take a path or a root keyword
# need none of this and do not use it.
module GateFixture
  def with_constants(owner, values)
    previous = values.keys.to_h { |name| [name, owner.const_get(name)] }
    values.each { |name, value| swap_constant(owner, name, value) }
    yield
  ensure
    previous&.each { |name, value| swap_constant(owner, name, value) }
  end

  # remove_const first, so redefining does not print "already initialized
  # constant" for every swap and bury the test output.
  def swap_constant(owner, name, value)
    owner.send(:remove_const, name) if owner.const_defined?(name, false)
    owner.const_set(name, value)
  end

  # Writes body at rel under dir, creating the directories rel names. Returns
  # the absolute path.
  def plant(dir, rel, body)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  # An apps.yml the deploy inventory accepts. Every gate that walks the fleet
  # reads the fleet from here, so a fixture tree needs one before it has any
  # apps at all.
  def plant_apps_yml(dir, *names)
    rows = names.map do |name|
      "  #{name}:\n    domain: #{name}.test\n    port: 1\n" \
        "    deploy_script: #{name}.sh\n    deploy_root: /home/#{name}\n"
    end
    plant(dir, "RAILS/apps.yml", "apps:\n#{rows.join}")
  end
end
