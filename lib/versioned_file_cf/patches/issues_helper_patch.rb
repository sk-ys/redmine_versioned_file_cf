# frozen_string_literal: true

module VersionedFileCf
  module Patches
    module IssuesHelperPatch
      def show_detail(detail, no_html = false, options = {})
        return super unless versioned_file_detail?(detail)

        show_versioned_file_detail(detail, no_html, options)
      end

      private

      def versioned_file_detail?(detail)
        detail.property == 'cf' && detail.custom_field&.field_format == 'versioned_file'
      end

      def show_versioned_file_detail(detail, no_html = false, options = {})
        label = detail.custom_field.name
        label = content_tag('strong', label) unless no_html

        old_value = versioned_file_detail_value(detail.old_value, no_html, options)
        new_value = versioned_file_detail_value(detail.value, no_html, options)

        message = if detail.value.present?
                    if detail.old_value.present?
                      l(:text_journal_changed, label: label, old: old_value, new: new_value)
                    else
                      l(:text_journal_set_to, label: label, value: new_value)
                    end
                  else
                    l(:text_journal_deleted, label: label, old: old_value)
                  end

        return message if no_html

        links = versioned_file_detail_links(detail, options)
        return message.html_safe if links.empty?

        safe_join([message.html_safe, " (".html_safe, safe_join(links, ' / '.html_safe), ')'.html_safe])
      end

      def versioned_file_detail_value(value, no_html = false, options = {})
        return '' if value.blank?

        attachment = versioned_file_detail_attachment(value)
        display = attachment&.filename.to_s.presence || value.to_s
        return display if no_html
        return content_tag('i', h(display)) unless attachment

        link_to_attachment(attachment, only_path: options[:only_path])
      end

      def versioned_file_detail_links(detail, options = {})
        current_revision = versioned_file_detail_revision(detail.value)
        old_revision = versioned_file_detail_revision(detail.old_value)
        target_revision = current_revision || old_revision
        return [] unless target_revision

        links = []
        compare_revision = current_revision && old_revision && current_revision != old_revision ? old_revision : current_revision&.previous_revision
        if current_revision && compare_revision
          diff_target = if options[:only_path] == false
                          diff_versioned_file_url(current_revision, compare_to_id: compare_revision.id)
                        else
                          diff_versioned_file_path(current_revision, compare_to_id: compare_revision.id)
                        end
          links << link_to(l(:label_diff), diff_target, title: l(:label_view_diff))
        end

        history_target = if options[:only_path] == false
                           history_versioned_files_url(custom_value_id: target_revision.custom_value_id)
                         else
                           history_versioned_files_path(custom_value_id: target_revision.custom_value_id)
                         end
        links << link_to(l(:label_history), history_target, title: l(:label_history))
        links
      end

      def versioned_file_detail_attachment(value)
        return if value.blank?
        return unless value.to_s.match?(/\A\d+\z/)

        Attachment.find_by(id: value.to_i)
      end

      def versioned_file_detail_revision(value)
        attachment = versioned_file_detail_attachment(value)
        return unless attachment&.container.is_a?(VersionedFileCf::FileRevision)

        attachment.container
      end
    end
  end
end
