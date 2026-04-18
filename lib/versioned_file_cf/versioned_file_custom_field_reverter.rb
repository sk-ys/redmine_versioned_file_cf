# frozen_string_literal: true

module VersionedFileCf
  class VersionedFileCustomFieldReverter < CustomFieldConversionBase

    Result = Struct.new(
      :custom_field,
      :total_values_count,
      :filled_values_count,
      :migrated_values_count,
      :deleted_revisions_count,
      :invalid_values,
      :dry_run,
      keyword_init: true
    ) do
      def success?
        invalid_values.empty?
      end
    end

    def call
      custom_field = load_custom_field!
      custom_values = CustomValue.where(custom_field_id: custom_field.id)
      filled_values_count = custom_values.where.not(value: [nil, '']).count
      invalid_values = []
      custom_values_to_revert = []
      deleted_revisions_count = 0

      custom_values.find_each do |custom_value|
        assessment = assess_custom_value(custom_value)

        case assessment[:status]
        when :already_reverted
          next
        when :revertible
          custom_values_to_revert << assessment[:payload]
          deleted_revisions_count += assessment[:payload][:revisions].size
        when :invalid
          invalid_values << assessment[:invalid_value]
        end
      end

      result = Result.new(
        custom_field: custom_field,
        total_values_count: custom_values.count,
        filled_values_count: filled_values_count,
        migrated_values_count: 0,
        deleted_revisions_count: deleted_revisions_count,
        invalid_values: invalid_values,
        dry_run: dry_run
      )

      return result if invalid_values.any? || dry_run

      reverted_values_count = 0
      deleted_revisions_count = 0

      CustomField.transaction do
        custom_values_to_revert.each do |payload|
          deleted_revisions_count += revert_custom_value!(payload)
          reverted_values_count += 1
        end

        change_field_format!(custom_field, 'attachment')
      end

      result.migrated_values_count = reverted_values_count
      result.deleted_revisions_count = deleted_revisions_count
      result
    end

    private

    def load_custom_field!
      super(
        expected_format: 'versioned_file',
        already_format: 'attachment',
        already_error_key: 'versioned_file_cf.tasks.revert_file_custom_field.error_already_file',
        invalid_error_key: 'versioned_file_cf.tasks.revert_file_custom_field.error_invalid_field_format'
      )
    end

    def assess_custom_value(custom_value)
      revisions = VersionedFileCf::FileRevision.where(custom_value_id: custom_value.id).order(revision_number: :desc, id: :desc).to_a
      return { status: :already_reverted } if revisions.empty? && custom_value.value.blank?

      active_revisions = revisions.select(&:active?)
      if active_revisions.size > 1
        return invalid_result(custom_value, custom_value.value, I18n.t('versioned_file_cf.tasks.revert_file_custom_field.reason_multiple_active_revisions'))
      end

      active_revision = active_revisions.first
      if active_revision.nil?
        return invalid_result(custom_value, custom_value.value, I18n.t('versioned_file_cf.tasks.revert_file_custom_field.reason_active_revision_missing')) unless revisions.empty?

        attachment_id = attachment_id_from(custom_value.value)
        return { status: :already_reverted } if attachment_id && Attachment.find_by(id: attachment_id)&.container == custom_value

        return invalid_result(custom_value, custom_value.value, I18n.t('versioned_file_cf.tasks.revert_file_custom_field.reason_active_revision_missing'))
      end

      attachment_id = attachment_id_from(custom_value.value)
      unless attachment_id && attachment_id == active_revision.attachment_id
        return invalid_result(custom_value, custom_value.value, I18n.t('versioned_file_cf.tasks.revert_file_custom_field.reason_attachment_id_invalid'))
      end

      attachment = active_revision.attachment
      unless attachment
        return invalid_result(custom_value, attachment_id, I18n.t('versioned_file_cf.tasks.revert_file_custom_field.reason_attachment_missing'))
      end

      unless attachment.container == active_revision
        return invalid_result(custom_value, attachment.id, I18n.t('versioned_file_cf.tasks.revert_file_custom_field.reason_attachment_not_owned'))
      end

      {
        status: :revertible,
        payload: {
          custom_value: custom_value,
          active_revision: active_revision,
          revisions: revisions,
          attachment: attachment
        }
      }
    end

    def revert_custom_value!(payload)
      custom_value = payload[:custom_value]
      active_revision = payload[:active_revision]
      attachment = payload[:attachment]
      revisions = payload[:revisions]

      attachment.update!(container: custom_value)
      custom_value.update_columns(value: attachment.id.to_s)

      deleted_revisions_count = 0
      revisions.each do |revision|
        if revision.id == active_revision.id
          revision.delete
        else
          revision.destroy!
        end
        deleted_revisions_count += 1
      end

      deleted_revisions_count
    end
  end
end