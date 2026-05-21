# frozen_string_literal: true

require_relative '../test_helper'
require 'tempfile'

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

  def test_set_custom_field_value_marks_identical_upload_as_unchanged_by_digest
    @custom_value.value = @format.set_custom_field_value(
      @custom_field,
      @custom_value,
      { file: uploaded_test_file('testfile.txt', 'text/plain') }
    )
    @format.after_save_custom_value(@custom_field, @custom_value)

    current_attachment = Attachment.find(@custom_value.value)

    assert_no_difference 'Attachment.count' do
      @custom_value.value = @format.set_custom_field_value(
        @custom_field,
        @custom_value,
        { file: uploaded_test_file('testfile.txt', 'text/plain') }
      )
    end

    assert_equal current_attachment.id.to_s, @custom_value.value
    assert_includes @format.validate_custom_value(@custom_value),
                    I18n.t(:error_versioned_file_unchanged, scope: :versioned_file_cf)
  end

  def test_after_save_custom_value_accepts_non_text_upload
    binary_file = Tempfile.new(['testfile', '.bin'])
    binary_file.binmode
    binary_file.write("\x00\x01\x02\x03".b)
    binary_file.rewind
    binary_file.define_singleton_method(:original_filename) { 'testfile.bin' }
    binary_file.define_singleton_method(:content_type) { 'application/octet-stream' }

    @custom_value.value = @format.set_custom_field_value(
      @custom_field,
      @custom_value,
      { file: binary_file }
    )

    assert_equal [], @format.validate_custom_value(@custom_value)

    revision = new_record(VersionedFileCf::FileRevision) do
      @format.after_save_custom_value(@custom_field, @custom_value)
    end

    assert_equal @custom_value, revision.custom_value
    assert_equal 'testfile.bin', revision.filename
    assert_equal 'testfile.bin', revision.attachment.filename
    assert_equal true, revision.active
    assert_equal revision.attachment.id.to_s, @custom_value.value
  ensure
    binary_file.close!
  end
end
