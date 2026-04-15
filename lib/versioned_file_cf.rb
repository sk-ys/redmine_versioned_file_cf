# frozen_string_literal: true

require_relative 'versioned_file_cf/field_format'
require_relative 'versioned_file_cf/patches/application_helper_patch'
require_relative 'versioned_file_cf/patches/issues_helper_patch'
require_relative 'versioned_file_cf/patches/customizable_patch'
require_relative 'versioned_file_cf/patches/custom_field_patch'
require_relative 'versioned_file_cf/patches/custom_value_patch'

module VersionedFileCf
  def self.setup!
    unless ApplicationHelper.ancestors.include?(VersionedFileCf::Patches::ApplicationHelperPatch)
      ApplicationHelper.send(:include, VersionedFileCf::Patches::ApplicationHelperPatch)
    end

    if defined?(IssuesHelper) && !IssuesHelper.ancestors.include?(VersionedFileCf::Patches::IssuesHelperPatch)
      IssuesHelper.prepend(VersionedFileCf::Patches::IssuesHelperPatch)
    end

    unless CustomValue.ancestors.include?(VersionedFileCf::Patches::CustomValuePatch)
      CustomValue.send(:include, VersionedFileCf::Patches::CustomValuePatch)
    end

    unless CustomField.ancestors.include?(VersionedFileCf::Patches::CustomFieldPatch)
      CustomField.send(:include, VersionedFileCf::Patches::CustomFieldPatch)
    end

    if defined?(Redmine::Acts::Customizable::InstanceMethods) &&
       !Redmine::Acts::Customizable::InstanceMethods.ancestors.include?(VersionedFileCf::Patches::CustomizablePatch)
      Redmine::Acts::Customizable::InstanceMethods.prepend(VersionedFileCf::Patches::CustomizablePatch)
    end

    true
  end

  def self.pending_revisions_for(customized)
    customized.instance_variable_get(:@versioned_file_pending_revisions) || {}
  end

  def self.pending_revision_for(customized, custom_field_id)
    pending_revisions_for(customized)[custom_field_id.to_i]
  end

  def self.store_pending_revision(customized, custom_field_id, payload)
    revisions = pending_revisions_for(customized).dup
    revisions[custom_field_id.to_i] = payload
    customized.instance_variable_set(:@versioned_file_pending_revisions, revisions)
  end

  def self.clear_pending_revision(customized, custom_field_id)
    revisions = pending_revisions_for(customized).dup
    revisions.delete(custom_field_id.to_i)
    customized.instance_variable_set(:@versioned_file_pending_revisions, revisions)
  end
end
