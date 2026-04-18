# frozen_string_literal: true

require_relative '../test_helper'

class VersionedFileCfVersionedFileCustomFieldReverterTest < ActiveSupport::TestCase
  def setup
    set_tmp_attachments_directory
    User.current = User.find(1)
    @issue = Issue.find(1)
  end

  def teardown
    User.current = nil
    set_fixtures_attachments_directory
  end

  def test_call_reverts_versioned_file_custom_field_to_attachment_and_deletes_history
    custom_field = create_issue_versioned_file_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    first_revision = create_revision(
      custom_value: custom_value,
      fixture: 'testfile.txt',
      content: "alpha\n",
      revision_number: 1,
      active: false
    )
    current_revision = create_revision(
      custom_value: custom_value,
      fixture: 'testfile.txt',
      content: "beta\n",
      revision_number: 2,
      active: true
    )

    assert_difference 'Attachment.count', -1 do
      result = VersionedFileCf::VersionedFileCustomFieldReverter.new(custom_field_id: custom_field.id).call

      assert_predicate result, :success?
      assert_equal 1, result.migrated_values_count
      assert_equal 2, result.deleted_revisions_count
    end

    assert_equal 'attachment', custom_field.reload.field_format
    assert_equal current_revision.attachment_id.to_s, custom_value.reload.value
    assert_equal custom_value, current_revision.attachment.reload.container
    assert_nil Attachment.find_by(id: first_revision.attachment_id)
    assert_equal 0, VersionedFileCf::FileRevision.where(custom_value_id: custom_value.id).count
  end

  def test_call_with_dry_run_does_not_persist_changes
    custom_field = create_issue_versioned_file_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    create_revision(
      custom_value: custom_value,
      fixture: 'testfile.txt',
      content: "alpha\n",
      revision_number: 1,
      active: true
    )

    assert_no_difference ['VersionedFileCf::FileRevision.count', 'Attachment.count'] do
      result = VersionedFileCf::VersionedFileCustomFieldReverter.new(custom_field_id: custom_field.id, dry_run: true).call

      assert_predicate result, :success?
      assert_equal 1, result.deleted_revisions_count
      assert_equal 0, result.migrated_values_count
      assert_equal true, result.dry_run
    end

    assert_equal 'versioned_file', custom_field.reload.field_format
  end

  def test_call_reports_invalid_values_without_active_revision
    custom_field = create_issue_versioned_file_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    create_revision(
      custom_value: custom_value,
      fixture: 'testfile.txt',
      content: "alpha\n",
      revision_number: 1,
      active: false
    )

    assert_no_difference ['VersionedFileCf::FileRevision.count', 'Attachment.count'] do
      result = VersionedFileCf::VersionedFileCustomFieldReverter.new(custom_field_id: custom_field.id).call

      assert_not result.success?
      assert_equal 1, result.invalid_values.size
      assert_equal I18n.t('versioned_file_cf.tasks.revert_file_custom_field.reason_active_revision_missing'), result.invalid_values.first.reason
    end

    assert_equal 'versioned_file', custom_field.reload.field_format
  end
end