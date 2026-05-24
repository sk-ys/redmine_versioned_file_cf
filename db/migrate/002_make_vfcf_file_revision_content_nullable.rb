# frozen_string_literal: true

class MakeVfcfFileRevisionContentNullable < ActiveRecord::Migration[6.1]
  def up
    change_column_null :vfcf_file_revisions, :content, true
  end

  def down
    # Ensure rollback does not fail when NULL values exist.
    execute <<~SQL.squish
      UPDATE vfcf_file_revisions
      SET content = ''
      WHERE content IS NULL
    SQL

    change_column_null :vfcf_file_revisions, :content, false
  end
end
