# frozen_string_literal: true

require_relative '../test_helper'

class VersionedFileCfFileCustomFieldMigratorTest < ActiveSupport::TestCase
  def setup
    set_tmp_attachments_directory
    User.current = User.find(1)
    @issue = Issue.find(1)
  end

  def teardown
    User.current = nil
    set_fixtures_attachments_directory
  end

  def test_call_migrates_attachment_custom_field_to_versioned_file
    custom_field = create_issue_attachment_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    attachment = create_attachment_for_custom_value(custom_value: custom_value, fixture: 'testfile.txt')

    result = VersionedFileCf::FileCustomFieldMigrator.new(custom_field_id: custom_field.id).call

    assert_predicate result, :success?
    assert_equal 1, result.migrated_values_count
    assert_equal 'versioned_file', custom_field.reload.field_format

    revision = VersionedFileCf::FileRevision.find_by!(custom_value_id: custom_value.id)
    assert_equal attachment.id, revision.attachment_id
    assert_equal attachment.filename, revision.filename
    assert_equal attachment.author, revision.author
    assert_equal true, revision.active
    assert_equal attachment.id.to_s, custom_value.reload.value
    assert_equal revision, attachment.reload.container
    assert_not_empty revision.content
  end

  def test_call_with_dry_run_does_not_persist_changes
    custom_field = create_issue_attachment_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    create_attachment_for_custom_value(custom_value: custom_value, fixture: 'testfile.txt')

    assert_no_difference ['VersionedFileCf::FileRevision.count'] do
      result = VersionedFileCf::FileCustomFieldMigrator.new(custom_field_id: custom_field.id, dry_run: true).call

      assert_predicate result, :success?
      assert_equal 0, result.migrated_values_count
      assert_equal true, result.dry_run
    end

    assert_equal 'attachment', custom_field.reload.field_format
  end

  def test_call_migrates_binary_attachment_without_text_content
    custom_field = create_issue_attachment_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    attachment = create_attachment_for_custom_value(
      custom_value: custom_value,
      fixture: '2006/07/060719210727_archive.zip',
      mime_type: 'application/zip'
    )

    assert_difference ['VersionedFileCf::FileRevision.count'], +1 do
      result = VersionedFileCf::FileCustomFieldMigrator.new(custom_field_id: custom_field.id).call

      assert_predicate result, :success?
      assert_equal 1, result.migrated_values_count
      assert_empty result.invalid_values
    end

    assert_equal 'versioned_file', custom_field.reload.field_format

    revision = VersionedFileCf::FileRevision.find_by!(custom_value_id: custom_value.id)
    assert_equal attachment.id, revision.attachment_id
    assert_nil revision.content
    assert_equal revision, attachment.reload.container
  end

  def test_call_completes_when_value_is_already_migrated
    custom_field = create_issue_attachment_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    revision = create_revision(
      custom_value: custom_value,
      fixture: 'testfile.txt',
      content: 'existing content',
      revision_number: 1,
      active: true
    )

    assert_no_difference ['VersionedFileCf::FileRevision.count'] do
      result = VersionedFileCf::FileCustomFieldMigrator.new(custom_field_id: custom_field.id).call

      assert_predicate result, :success?
      assert_equal 1, result.migrated_values_count
    end

    assert_equal 'versioned_file', custom_field.reload.field_format
    assert_equal revision, revision.attachment.reload.container
  end
end
