# frozen_string_literal: true

require_relative '../test_helper'

class VersionedFileCfCustomFieldConversionsControllerTest < Redmine::ControllerTest
  tests VersionedFileCf::CustomFieldConversionsController

  def setup
    set_tmp_attachments_directory
    User.current = User.find(1)
    @request.session[:user_id] = 1
    @issue = Issue.find(1)
  end

  def teardown
    User.current = nil
    set_fixtures_attachments_directory
  end

  def test_convert_to_versioned_file
    custom_field = create_issue_attachment_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    create_attachment_for_custom_value(custom_value: custom_value, fixture: 'testfile.txt')

    assert_difference('VersionedFileCf::FileRevision.count', 1) do
      post :convert_to_versioned_file, params: { id: custom_field.id }
    end

    assert_redirected_to edit_custom_field_path(custom_field)
    assert_equal 'versioned_file', custom_field.reload.field_format
    assert_equal I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.label_done', count: 1), flash[:notice]
  end

  def test_convert_to_file_deletes_revision_history
    custom_field = create_issue_versioned_file_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field)
    create_revision(
      custom_value: custom_value,
      fixture: 'testfile.txt',
      content: 'before',
      revision_number: 1,
      active: false
    )
    create_revision(
      custom_value: custom_value,
      fixture: 'testfile.txt',
      content: 'after',
      revision_number: 2,
      active: true
    )

    assert_difference('VersionedFileCf::FileRevision.count', -2) do
      post :convert_to_file, params: { id: custom_field.id }
    end

    assert_redirected_to edit_custom_field_path(custom_field)
    assert_equal 'attachment', custom_field.reload.field_format
    assert_equal I18n.t('versioned_file_cf.tasks.revert_file_custom_field.label_done', count: 1, revisions: 2), flash[:notice]
  end

  def test_convert_to_file_sets_flash_error_for_invalid_values
    custom_field = create_issue_versioned_file_custom_field
    custom_value = create_custom_value(issue: @issue, custom_field: custom_field, value: '999999')
    VersionedFileCf::FileRevision.create!(
      custom_value: custom_value,
      attachment: Attachment.create!(
        container: custom_value,
        file: uploaded_test_file('testfile.txt', 'text/plain'),
        author: User.find(1)
      ),
      author: User.find(1),
      filename: 'testfile.txt',
      content: 'broken',
      revision_number: 1,
      active: true
    )

    post :convert_to_file, params: { id: custom_field.id }

    assert_redirected_to edit_custom_field_path(custom_field)
    assert_match I18n.t('versioned_file_cf.tasks.common.label_invalid_header', count: 1), flash[:error]
    assert_equal 'versioned_file', custom_field.reload.field_format
  end
end