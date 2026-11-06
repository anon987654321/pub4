# frozen_string_literal: true

# `object_id` is a method every Ruby object already has, and an AR attribute of
# that name silently replaces it on every ActivityEvent instance. Rails permits
# it — dangerous_attribute_method? compares the method's owner on Base and on
# its superclass, and for object_id both are Object, so the check returns false
# — which is why this shipped and worked. It still means the one method whose
# contract is "a number unique to this object for its lifetime" returns a
# foreign key instead.
#
# subject_type/subject_id is not a new name invented here. Shared::DomainEvent
# has always built its payload as `subject_type:`/`subject_id:`, and
# Shared::AuditEvent stores `target_type`/`target_id` for the same idea. Only
# the ActivityEvent columns were called object_*, and the recorder in between
# translated. This removes the translation.
class RenameActivityEventObjectToSubject < ActiveRecord::Migration[8.1]
  def up
    remove_index :activity_events, %i[object_type object_id]
    rename_column :activity_events, :object_type, :subject_type
    rename_column :activity_events, :object_id, :subject_id
    add_index :activity_events, %i[subject_type subject_id]
  end

  def down
    remove_index :activity_events, %i[subject_type subject_id]
    rename_column :activity_events, :subject_type, :object_type
    rename_column :activity_events, :subject_id, :object_id
    add_index :activity_events, %i[object_type object_id]
  end
end
