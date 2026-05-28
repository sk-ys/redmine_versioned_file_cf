# frozen_string_literal: true

module VersionedFileCf
  class FieldFormat < Redmine::FieldFormat::TextFormat
    add 'versioned_file'

    self.form_partial = 'custom_fields/formats/versioned_file'
    self.change_as_diff = false
    self.change_no_details = true
    self.bulk_edit_supported = false
    field_attributes :extensions_allowed

    def formatted_custom_value(view, custom_value, html = false)
      persisted_custom_value = custom_value.customized.custom_value_for(custom_value.custom_field)
      revision = current_revision_for(persisted_custom_value)
      attachment = revision&.attachment || attachment_from_value(custom_value.value)
      display_value = attachment&.filename.to_s.presence || revision&.filename.to_s.presence || custom_value.value.to_s
      return display_value unless html

      view.render(
        partial: 'versioned_files/current',
        locals: {
          custom_value: custom_value,
          revision: revision,
          attachment: attachment,
          value: display_value
        }
      )
    end

    def set_custom_field_value(custom_field, custom_field_value, value)
      payload = normalize_value(custom_field, custom_field_value, value)
      custom_field_value.instance_variable_set(:@attachment_present, payload[:attachment_present])

      if %i[upload clear].include?(payload[:action]) || payload[:error].present?
        VersionedFileCf.store_pending_revision(custom_field_value.customized, custom_field.id, payload)
      else
        VersionedFileCf.clear_pending_revision(custom_field_value.customized, custom_field.id)
      end
      payload[:value].to_s
    end

    def validate_custom_value(custom_value)
      payload = VersionedFileCf.pending_revision_for(custom_value.customized, custom_value.custom_field_id)

      errors = []
      if custom_value.value.blank? && custom_value.instance_variable_get(:@attachment_present)
        errors << ::I18n.t('activerecord.errors.messages.invalid')
      end

      if payload
        errors << payload[:error] if payload[:error].present?

        attachment = payload[:attachment]
        extensions = custom_value.custom_field.extensions_allowed
        if attachment && extensions.present? && !attachment.extension_in?(extensions)
          errors << "#{::I18n.t('activerecord.errors.messages.invalid')} (#{l(:setting_attachment_extensions_allowed)}: #{extensions})"
        end
      end

      errors.uniq
    end

    def after_save_custom_value(custom_field, custom_value)
      payload = VersionedFileCf.pending_revision_for(custom_value.customized, custom_field.id)
      return unless payload

      revisions_scope(custom_value).current.update_all(active: false)

      if payload[:action] == :upload && payload[:attachment]
        next_revision_number = revisions_scope(custom_value).maximum(:revision_number).to_i + 1
        revision = VersionedFileCf::FileRevision.create!(
          custom_value: custom_value,
          attachment: payload[:attachment],
          author: User.current,
          filename: payload[:attachment].filename,
          content: payload[:content].to_s,
          revision_number: next_revision_number,
          active: true
        )
        payload[:attachment].update!(container: revision)
      end
    ensure
      VersionedFileCf.clear_pending_revision(custom_value.customized, custom_field.id)
    end

    def edit_tag(view, tag_id, tag_name, custom_value, options = {})
      persisted_custom_value = custom_value.customized.custom_value_for(custom_value.custom_field)
      revision = current_revision_for(persisted_custom_value)
      attachment = revision&.attachment || attachment_from_value(persisted_custom_value&.value || custom_value.value)
      payload = VersionedFileCf.pending_revision_for(custom_value.customized, custom_value.custom_field_id)
      attachment ||= payload[:attachment] if payload&.dig(:action) == :upload

      view.hidden_field_tag("#{tag_name}[blank]", '', class: 'versioned-file-cf-form') +
        view.render(
          partial: 'attachments/form',
          locals: {
            attachment_param: tag_name,
            multiple: false,
            description: true,
            saved_attachments: [attachment].compact,
            filedrop: true,
            attachment_format_custom_field: true
          }
        )
    end

    private

    def normalize_value(custom_field, custom_field_value, value)
      payload = {
        action: :noop,
        attachment: nil,
        content: nil,
        description: nil,
        value: '',
        error: nil,
        attachment_present: false
      }

      value = normalize_hash(value)
      if value.is_a?(Hash)
        value = value.except('blank', :blank)

        if value.values.any? && value.values.all? { |entry| entry.is_a?(Hash) }
          value = normalize_hash(value.values.first)
        end

        attachment_attributes = extract_attachment_attributes(value)

        if value['id'].present? || value[:id].present?
          payload[:attachment_present] = true
          attachment = find_existing_attachment(custom_field_value, value['id'] || value[:id])
          set_payload_from_existing_attachment(payload, attachment)
          apply_attachment_attributes!(payload, attachment, attachment_attributes)
        elsif value['token'].present? || value[:token].present?
          payload[:attachment_present] = true
          attachment = Attachment.find_by_token(value['token'] || value[:token])
          build_payload_from_attachment(payload, attachment)
          apply_attachment_attributes!(payload, attachment, attachment_attributes)
          discard_unchanged_upload!(custom_field_value, payload)
        elsif value.key?('file') || value.key?(:file)
          payload[:attachment_present] = true
          attachment = Attachment.new(file: value['file'] || value[:file], author: User.current)
          if attachment.save
            build_payload_from_attachment(payload, attachment)
            apply_attachment_attributes!(payload, attachment, attachment_attributes)
            discard_unchanged_upload!(custom_field_value, payload)
          else
            payload[:error] = ::I18n.t('activerecord.errors.messages.invalid')
          end
        else
          payload[:action] = :clear
        end
      elsif value.present?
        payload[:attachment_present] = true
        attachment = find_existing_attachment(custom_field_value, value)
        set_payload_from_existing_attachment(payload, attachment)
      else
        payload[:action] = :clear
      end

      payload
    end

    def normalize_hash(value)
      return value unless value.is_a?(Hash)

      value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
    end

    def set_payload_from_existing_attachment(payload, attachment)
      if attachment.nil?
        payload[:error] = ::I18n.t('activerecord.errors.messages.invalid')
        return payload
      end

      payload[:action] = :keep
      payload[:attachment] = attachment
      payload[:value] = attachment.id.to_s
      payload[:description] = attachment.description.to_s
      if attachment.container.is_a?(::VersionedFileCf::FileRevision) && attachment.readable? && attachment.is_text?
        payload[:content] = attachment.container&.content.to_s
      end
      payload
    end

    def build_payload_from_attachment(payload, attachment)
      if attachment.nil?
        payload[:error] = ::I18n.t('activerecord.errors.messages.invalid')
        return payload
      end

      payload[:attachment] = attachment
      payload[:value] = attachment.id.to_s
      payload[:description] = attachment.description.to_s

      payload[:action] = :upload

      if attachment.readable? && attachment.is_text?
        payload[:content] = read_text(attachment)
      end

      payload
    end

    def discard_unchanged_upload!(custom_field_value, payload)
      return payload unless payload[:action] == :upload && payload[:attachment]
      return payload unless Setting.plugin_redmine_versioned_file_cf['compare_attachments_when_uploading'] != '0'
      if Setting.plugin_redmine_versioned_file_cf['compare_attachments_by_hash'] != '0'
        return payload unless payload[:attachment].digest == current_attachment_for(custom_field_value)&.digest
      else
        return payload unless FileUtils.compare_file(payload[:attachment].diskfile, current_attachment_for(custom_field_value)&.diskfile)
      end
      return payload unless payload[:attachment].filename.to_s == current_filename_for(custom_field_value)
      return payload unless payload[:attachment].description.to_s == current_description_for(custom_field_value)

      payload[:attachment].destroy
      payload[:action] = :keep
      payload[:attachment] = current_attachment_for(custom_field_value)
      payload[:value] = payload[:attachment]&.id.to_s
      payload[:description] = payload[:attachment]&.description.to_s
      payload[:error] = ::I18n.t(:error_versioned_file_unchanged, scope: :versioned_file_cf)
      payload
    end

    def extract_attachment_attributes(value)
      attributes = {}
      if value.key?('filename') || value.key?(:filename)
        attributes[:filename] = value['filename'] || value[:filename]
      end
      if value.key?('description') || value.key?(:description)
        attributes[:description] = (value['description'] || value[:description]).to_s.strip
      end
      attributes
    end

    def apply_attachment_attributes!(payload, attachment, attributes)
      return payload if payload[:error].present?
      return payload if attachment.nil? || attributes.blank?

      attachment.assign_attributes(attributes)
      if attachment.save
        payload[:description] = attachment.description.to_s
      else
        payload[:error] = ::I18n.t('activerecord.errors.messages.invalid')
      end
      payload
    end

    def find_existing_attachment(custom_field_value, id)
      attachment = attachment_from_value(id)
      return if attachment.nil?

      if attachment.container.is_a?(::VersionedFileCf::FileRevision)
        revision = attachment.container
        return attachment if revision.custom_value == custom_field_value.customized.custom_value_for(custom_field_value.custom_field)
      elsif attachment.container.is_a?(CustomValue)
        return attachment if attachment.container == custom_field_value.customized.custom_value_for(custom_field_value.custom_field)
      end

      nil
    end

    def read_text(attachment)
      content = File.binread(attachment.diskfile)
      content.force_encoding(Encoding::UTF_8)
      return content if content.valid_encoding?

      content.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
    end

    def revisions_scope(custom_value)
      return VersionedFileCf::FileRevision.none unless custom_value&.id

      VersionedFileCf::FileRevision.where(custom_value_id: custom_value.id)
    end

    def current_revision_for(custom_value)
      revisions_scope(custom_value).current.order(revision_number: :desc, id: :desc).first
    end

    def current_content_for(custom_field_value)
      current_custom_value = custom_field_value.customized.custom_value_for(custom_field_value.custom_field)
      current_revision = current_revision_for(current_custom_value)
      return current_revision.content.to_s if current_revision

      attachment = attachment_from_value(current_custom_value&.value)
      return nil unless attachment&.readable? && attachment.is_text?

      read_text(attachment)
    end

    def current_filename_for(custom_field_value)
      current_custom_value = custom_field_value.customized.custom_value_for(custom_field_value.custom_field)
      current_revision = current_revision_for(current_custom_value)
      return current_revision.filename.to_s if current_revision

      attachment_from_value(current_custom_value&.value)&.filename.to_s
    end

    def current_description_for(custom_field_value)
      current_custom_value = custom_field_value.customized.custom_value_for(custom_field_value.custom_field)
      current_revision = current_revision_for(current_custom_value)
      return current_revision.attachment&.description.to_s if current_revision

      attachment_from_value(current_custom_value&.value)&.description.to_s
    end

    def current_attachment_for(custom_field_value)
      current_custom_value = custom_field_value.customized.custom_value_for(custom_field_value.custom_field)
      current_revision = current_revision_for(current_custom_value)
      return current_revision.attachment if current_revision

      attachment_from_value(current_custom_value&.value)
    end

    def attachment_from_value(value)
      return if value.blank?
      return unless value.to_s.match?(/\A\d+\z/)

      Attachment.find_by_id(value.to_i)
    end
  end
end
