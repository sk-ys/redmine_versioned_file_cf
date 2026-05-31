# frozen_string_literal: true

require_relative 'lib/versioned_file_cf'

Redmine::Plugin.register :redmine_versioned_file_cf do
  name 'Redmine Revision File Custom Field'
  author 'sk-ys'
  description 'Adds a revision-managed text file custom field.'
  version '0.2.1'
  requires_redmine version_or_higher: '6.1'
  url 'https://github.com/sk-ys/redmine_versioned_file_cf'
  author_url 'https://github.com/sk-ys'
  settings default: {
    compare_attachments_when_uploading: '1',
    compare_attachments_by_hash: '1',
  },
  partial: 'settings/versioned_file_cf_settings'

  permission :view_versioned_file_revisions, { versioned_files: [:history, :compare, :diff] }
  permission :update_versioned_file_description, { versioned_files: [:update_description] }
  permission :remove_file_revision, { versioned_files: [:destroy] }
end

VersionedFileCf.setup!
