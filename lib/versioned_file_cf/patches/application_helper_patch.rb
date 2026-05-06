# frozen_string_literal: true

module VersionedFileCf
  module Patches
    module ApplicationHelperPatch
      BREADCRUMB_SEPARATOR = ' &raquo; '.html_safe

      def link_to_attachment_container(attachment_container)
        breadcrumb = versioned_file_attachment_breadcrumb(attachment_container)
        return breadcrumb if breadcrumb

        super
      end

      private

      def versioned_file_attachment_breadcrumb(attachment_container)
        return nil unless attachment_container.is_a?(VersionedFileCf::FileRevision)

        custom_field = attachment_container.custom_field
        custom_value_id = attachment_container.custom_value_id
        return nil unless custom_field && custom_value_id

        crumbs = [
          link_to_record(attachment_container.custom_value.customized),
          link_to(custom_field.name + ' - ' + l(:label_history), history_versioned_files_path(custom_value_id: custom_value_id))
        ]

        content_tag(:span, safe_join(crumbs, BREADCRUMB_SEPARATOR), class: 'revision-file-breadcrumb')
      end
    end
  end
end
