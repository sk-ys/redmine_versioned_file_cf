# frozen_string_literal: true

require_relative 'lib/versioned_file_cf'

Redmine::Plugin.register :redmine_versioned_file_cf do
  name 'Redmine Revision File Custom Field'
  author 'sk-ys'
  description 'Adds a revision-managed text file custom field.'
  version '0.2.1'
  requires_redmine version_or_higher: '6.1'
end

VersionedFileCf.setup!
