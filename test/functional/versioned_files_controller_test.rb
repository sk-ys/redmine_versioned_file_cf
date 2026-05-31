# frozen_string_literal: true

require_relative '../test_helper'

class VersionedFilesControllerTest < Redmine::ControllerTest
  def setup
    User.current = nil
    set_tmp_attachments_directory

    @issue = Issue.find(1)
    @custom_field = create_issue_versioned_file_custom_field
    @custom_value = create_custom_value(issue: @issue, custom_field: @custom_field)
    @previous_revision = create_revision(
      custom_value: @custom_value,
      fixture: 'testfile.txt',
      content: "alpha\n",
      revision_number: 1,
      active: false
    )
    @revision = create_revision(
      custom_value: @custom_value,
      fixture: 'testfile.txt',
      content: "beta\n",
      revision_number: 2,
      active: true
    )
  end

  def teardown
    set_fixtures_attachments_directory
  end

  def test_history
    @request.session[:user_id] = 1

    get(:history, params: { custom_value_id: @custom_value.id })

    assert_response :success
    assert_select 'td.id', text: 'r2'
    assert_select 'td.filename', text: /testfile\.txt/
  end

  def test_diff
    @request.session[:user_id] = 1

    get(:diff, params: { id: @revision.id })

    assert_response :success
    assert_select 'table.filecontent.diffcontent'
    assert_match 'beta', @response.body
  end

  def test_diff_denies_access_for_invisible_issue
    private_field = create_issue_versioned_file_custom_field(name: 'Private revision file')
    private_custom_value = create_custom_value(issue: Issue.find(6), custom_field: private_field)
    private_previous_revision = create_revision(
      custom_value: private_custom_value,
      fixture: 'testfile.txt',
      content: "private alpha\n",
      revision_number: 1,
      active: false
    )
    private_revision = create_revision(
      custom_value: private_custom_value,
      fixture: 'testfile.txt',
      content: "private beta\n",
      revision_number: 2,
      active: true
    )
    @request.session[:user_id] = 7

    get(:diff, params: { id: private_revision.id, compare_to_id: private_previous_revision.id })

    assert_response :forbidden
  end

  def test_update_description_updates_attachment_for_authorized_user
    @request.session[:user_id] = 1

    post(:update_description, params: { id: @revision.id, description: 'updated by admin' }, xhr: true)

    assert_response :success
    assert_equal 'updated by admin', @revision.attachment.reload.description
  end

  def test_update_description_denies_access_without_permission
    @request.session[:user_id] = 2

    post(:update_description, params: { id: @revision.id, description: 'should fail' }, xhr: true)

    assert_response :forbidden
    assert_not_equal 'should fail', @revision.attachment.reload.description
  end

  def test_destroy_removes_inactive_revision_for_authorized_user
    @request.session[:user_id] = 1

    assert_difference('VersionedFileCf::FileRevision.count', -1) do
      assert_difference('Attachment.count', -1) do
        delete(:destroy, params: { id: @previous_revision.id })
      end
    end

    assert_redirected_to history_versioned_files_path(custom_value_id: @custom_value.id)
    assert_equal I18n.t(:notice_revision_removed, scope: :versioned_file_cf), flash[:notice]
    assert_not VersionedFileCf::FileRevision.exists?(@previous_revision.id)
  end

  def test_destroy_rejects_active_revision
    @request.session[:user_id] = 1

    assert_no_difference('VersionedFileCf::FileRevision.count') do
      delete(:destroy, params: { id: @revision.id })
    end

    assert_redirected_to history_versioned_files_path(custom_value_id: @custom_value.id)
    assert_equal I18n.t(:error_active_record_cannot_be_deleted, scope: :versioned_file_cf), flash[:error]
    assert VersionedFileCf::FileRevision.exists?(@revision.id)
  end

  def test_destroy_denies_access_without_permission
    @request.session[:user_id] = 2

    assert_no_difference('VersionedFileCf::FileRevision.count') do
      delete(:destroy, params: { id: @previous_revision.id })
    end

    assert_response :forbidden
    assert VersionedFileCf::FileRevision.exists?(@previous_revision.id)
  end

  def test_restore_creates_new_revision_for_authorized_user
    @request.session[:user_id] = 1
    old_attachment_id = @custom_value.value

    assert_difference('VersionedFileCf::FileRevision.count', 1) do
      assert_difference('Journal.count', 1) do
        post(:restore, params: { id: @previous_revision.id })
      end
    end

    restored_revision = VersionedFileCf::FileRevision.order(id: :desc).first
    assert_equal @custom_value.id, restored_revision.custom_value_id
    assert_equal @previous_revision.attachment_id, restored_revision.attachment_id
    assert_equal 1, restored_revision.author_id
    assert restored_revision.active?
    assert_not @revision.reload.active?
    assert_equal @previous_revision.attachment_id.to_s, @custom_value.reload.value
    journal = @issue.journals.order(id: :desc).first
    detail = journal.details.find_by(property: 'cf', prop_key: @custom_field.id.to_s)
    assert_not_nil detail
    assert_equal old_attachment_id, detail.old_value
    assert_equal @previous_revision.attachment_id.to_s, detail.value
    assert journal.notes.blank?
    assert_redirected_to history_versioned_files_path(custom_value_id: @custom_value.id)
    assert_equal I18n.t(:notice_revision_restored, scope: :versioned_file_cf, revision: restored_revision.revision_number), flash[:notice]
  end

  def test_restore_denies_access_without_permission
    @request.session[:user_id] = 2

    assert_no_difference('VersionedFileCf::FileRevision.count') do
      post(:restore, params: { id: @previous_revision.id })
    end

    assert_response :forbidden
  end

  def test_restore_aborts_when_issue_is_invalid
    @issue.update_column(:subject, '')
    @request.session[:user_id] = 1

    assert_no_difference('VersionedFileCf::FileRevision.count') do
      post(:restore, params: { id: @previous_revision.id })
    end

    assert_redirected_to history_versioned_files_path(custom_value_id: @custom_value.id)
    assert flash[:error].present?
    assert @revision.reload.active?
    assert_equal @revision.attachment_id.to_s, @custom_value.reload.value
  ensure
    @issue.update_column(:subject, 'Cannot print recipes')
  end
end
