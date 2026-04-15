# frozen_string_literal: true

require_relative '../../../test/test_helper'

plugin = Redmine::Plugin.find(:redmine_versioned_file_cf)
current_version = Redmine::Plugin::Migrator.current_version(plugin)

if plugin.latest_migration.to_i > current_version
  plugin.migrate
  VersionedFileCf::FileRevision.reset_column_information
end

module VersionedFileCfTestHelper
  def create_issue_versioned_file_custom_field(name: 'Revision file')
    field = IssueCustomField.new(
      name: name,
      field_format: 'versioned_file',
      is_for_all: true,
      trackers: [Tracker.find(1)]
    )
    assert field.save, field.errors.full_messages.join(', ')
    field
  end

  def create_custom_value(issue: Issue.find(1), custom_field: create_issue_versioned_file_custom_field, value: '')
    CustomValue.create!(customized: issue, custom_field: custom_field, value: value)
  end

  def create_revision(custom_value:, fixture:, content:, revision_number:, active:, author: User.find(1))
    attachment = Attachment.create!(
      container: custom_value,
      file: uploaded_test_file(fixture, Rack::Mime.mime_type(File.extname(fixture), 'text/plain')),
      author: author
    )

    revision = VersionedFileCf::FileRevision.create!(
      custom_value: custom_value,
      attachment: attachment,
      author: author,
      filename: attachment.filename,
      content: content,
      revision_number: revision_number,
      active: active
    )

    attachment.update!(container: revision)
    custom_value.update!(value: attachment.id.to_s) if active
    revision
  end
end

class ActiveSupport::TestCase
  include VersionedFileCfTestHelper
end

class Redmine::ControllerTest
  include VersionedFileCfTestHelper
end