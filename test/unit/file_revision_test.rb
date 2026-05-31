# frozen_string_literal: true

require_relative '../test_helper'

class VersionedFileCfFileRevisionTest < ActiveSupport::TestCase
  def setup
    set_tmp_attachments_directory
    User.current = User.find(1)
    @custom_field = create_issue_versioned_file_custom_field
    @custom_value = create_custom_value(issue: Issue.find(1), custom_field: @custom_field)
  end

  def teardown
    User.current = nil
    set_fixtures_attachments_directory
  end

  def test_destroy_rejects_active_revision
    revision = create_revision(
      custom_value: @custom_value,
      fixture: 'testfile.txt',
      content: "active revision\n",
      revision_number: 1,
      active: true
    )

    assert_no_difference('VersionedFileCf::FileRevision.count') do
      assert_not revision.destroy
    end

    assert_equal I18n.t(:error_active_record_cannot_be_deleted, scope: :versioned_file_cf), revision.errors[:base].first
    assert VersionedFileCf::FileRevision.exists?(revision.id)
    assert Attachment.exists?(revision.attachment_id)
  end

  def test_destroy_allows_inactive_revision_and_removes_attachment
    revision = create_revision(
      custom_value: @custom_value,
      fixture: 'testfile.txt',
      content: "inactive revision\n",
      revision_number: 1,
      active: false
    )

    assert_difference('VersionedFileCf::FileRevision.count', -1) do
      assert_difference('Attachment.count', -1) do
        assert revision.destroy
      end
    end

    assert_not VersionedFileCf::FileRevision.exists?(revision.id)
    assert_not Attachment.exists?(revision.attachment_id)
  end

  def test_destroy_keeps_attachment_when_referenced_by_another_revision
    revision = create_revision(
      custom_value: @custom_value,
      fixture: 'testfile.txt',
      content: "inactive revision\n",
      revision_number: 1,
      active: false
    )
    restored_revision = VersionedFileCf::FileRevision.create!(
      custom_value: @custom_value,
      attachment: revision.attachment,
      author: User.find(1),
      filename: revision.filename,
      content: "restored revision\n",
      revision_number: 2,
      active: true
    )

    assert_difference('VersionedFileCf::FileRevision.count', -1) do
      assert_no_difference('Attachment.count') do
        assert revision.destroy
      end
    end

    assert_not VersionedFileCf::FileRevision.exists?(revision.id)
    assert VersionedFileCf::FileRevision.exists?(restored_revision.id)
    assert Attachment.exists?(restored_revision.attachment_id)
  end
end
