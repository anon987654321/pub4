# frozen_string_literal: true

# Rails deduplicates before_action callbacks by FILTER NAME. Declaring the same
# filter twice does not add a second gate -- the later declaration replaces the
# earlier one, and its `only:`/`except:` becomes the whole scope.
#
# That turns an ordinary-looking edit into a silent authorisation hole, and it
# has happened twice in this tree:
#
#   amber ItemsController      before_action :require_real_user
#                              before_action :require_real_user, only: [:share]
#     The unrestricted gate on the first line became :share-only. index, new,
#     create, edit, update and destroy were left open; an anonymous
#     GET /items/new returned 200 on the running app.
#
#   brgen PostsController      before_action :require_real_user, only: %i[edit update destroy]
#                              before_action :require_real_user, only: [:share]
#     edit/update/destroy lost the gate. authorize_owner still covered them, so
#     nothing failed visibly -- which is exactly why a source read did not catch
#     it and the callback chain did.
#
# Both were added by a commit CLOSING a hole on :share. The fix opened others.
#
# This reads the source rather than booting: it runs under bare ruby with the
# rest of RAILS/test, and a controller declaring one filter twice is wrong
# regardless of what the chain resolves to.
require "minitest/autorun"

class CallbackNarrowingTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  CONTROLLERS = Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,shared}/**/app/controllers/**/*.rb"))
                   .reject { |f| f.include?("/vendor/") }

  def test_no_controller_declares_the_same_before_action_filter_twice
    offenders = CONTROLLERS.filter_map do |file|
      declarations = File.readlines(file).each_with_index.filter_map do |line, i|
        next if line =~ /^\s*#/

        name = line[/^\s*before_action\s+:(\w+)/, 1]
        [name, i + 1, line.strip] if name
      end
      repeated = declarations.group_by(&:first).select { |_, rows| rows.size > 1 }
      next if repeated.empty?

      repeated.map do |name, rows|
        "#{file.sub(ROOT + "/", "")}: :#{name} declared #{rows.size}x " \
          "(lines #{rows.map { |r| r[1] }.join(", ")}) — Rails keeps ONE; " \
          "the last `only:`/`except:` becomes the entire scope"
      end
    end.flatten

    assert_empty offenders,
                 "A repeated before_action silently narrows the gate rather than adding one. " \
                 "Merge them into a single declaration:\n  " + offenders.join("\n  ")
  end
end
