# frozen_string_literal: true

require_relative '../test_helper'

class VersionedFileCfCustomValuePatchTest < ActiveSupport::TestCase
  def setup
    set_tmp_attachments_directory
    User.current = User.find(1)
    @custom_field = create_issue_versioned_file_custom_field
    @custom_value = create_custom_value(issue: Issue.find(1), custom_field: @custom_field)
    @revision = create_revision(
      custom_value: @custom_value,
      fixture: 'testfile.txt',
      content: "alpha\n",
      revision_number: 1,
      active: true
    )
  end

  def teardown
    User.current = nil
    set_fixtures_attachments_directory
  end

  def test_destroying_custom_value_removes_revisions_and_attachment
    attachment_id = @revision.attachment_id

    assert_difference ['VersionedFileCf::FileRevision.count', 'Attachment.count'], -1 do
      @custom_value.destroy
    end

    assert_nil VersionedFileCf::FileRevision.find_by(id: @revision.id)
    assert_nil Attachment.find_by(id: attachment_id)
  end
end