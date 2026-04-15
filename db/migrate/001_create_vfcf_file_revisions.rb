# frozen_string_literal: true

class CreateVfcfFileRevisions < ActiveRecord::Migration[6.1]
  def change
    create_table :vfcf_file_revisions do |t|
      t.references :custom_value, null: false, type: :integer, foreign_key: { on_delete: :cascade }
      t.references :attachment, null: false, type: :integer, foreign_key: true
      t.references :author, type: :integer, foreign_key: { to_table: :users }
      t.integer :revision_number, null: false
      t.string :filename, null: false
      t.text :content, null: false
      t.boolean :active, null: false, default: false

      t.timestamps
    end

    add_index :vfcf_file_revisions, [:custom_value_id, :revision_number], unique: true, name: 'idx_vfcf_file_revisions_on_cv_and_rev'
    add_index :vfcf_file_revisions, [:custom_value_id, :active], name: 'idx_vfcf_file_revisions_on_cv_and_active'
  end
end