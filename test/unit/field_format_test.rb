# frozen_string_literal: true

require_relative '../test_helper'

class VersionedFileCfFieldFormatTest < ActiveSupport::TestCase
  def setup
    set_tmp_attachments_directory
    User.current = User.find(1)
    @issue = Issue.find(1)
    @custom_field = create_issue_versioned_file_custom_field
    @custom_value = create_custom_value(issue: @issue, custom_field: @custom_field)
    @format = Redmine::FieldFormat.find('versioned_file')
  end

  def teardown
    User.current = nil
    set_fixtures_attachments_directory
  end

  def test_after_save_custom_value_creates_active_revision_for_text_upload
    @custom_value.value = @format.set_custom_field_value(
      @custom_field,
      @custom_value,
      { file: uploaded_test_file('testfile.txt', 'text/plain') }
    )

    assert_equal [], @format.validate_custom_value(@custom_value)

    revision = new_record(VersionedFileCf::FileRevision) do
      @format.after_save_custom_value(@custom_field, @custom_value)
    end

    assert_equal @custom_value, revision.custom_value
    assert_equal 'testfile.txt', revision.filename
    assert_equal 'testfile.txt', revision.attachment.filename
    assert_equal true, revision.active
    assert_equal User.find(1), revision.author
    assert_equal revision.attachment.id.to_s, @custom_value.value
  end

  def test_validate_custom_value_rejects_binary_upload
    @custom_value.value = @format.set_custom_field_value(
      @custom_field,
      @custom_value,
      { file: uploaded_test_file('2006/07/060719210727_archive.zip', 'application/zip') }
    )

    errors = @format.validate_custom_value(@custom_value)

    assert_include I18n.t(:error_versioned_file_not_text, scope: :versioned_file_cf), errors.join("\n")
    assert_no_difference 'VersionedFileCf::FileRevision.count' do
      @format.after_save_custom_value(@custom_field, @custom_value)
    end
  end
end