# frozen_string_literal: true

module VersionedFileCf
  class FileCustomFieldMigrator < CustomFieldConversionBase

    Result = Struct.new(
      :custom_field,
      :total_values_count,
      :filled_values_count,
      :migrated_values_count,
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
      populated_values = custom_values.where.not(value: [nil, ''])
      invalid_values = []
      custom_values_to_migrate = []
      already_migrated_count = 0

      populated_values.find_each do |custom_value|
        assessment = assess_custom_value(custom_value)

        case assessment[:status]
        when :already_migrated
          already_migrated_count += 1
        when :migratable
          custom_values_to_migrate << custom_value
        when :invalid
          invalid_values << assessment[:invalid_value]
        end
      end

      result = Result.new(
        custom_field: custom_field,
        total_values_count: custom_values.count,
        filled_values_count: populated_values.count,
        migrated_values_count: already_migrated_count,
        invalid_values: invalid_values,
        dry_run: dry_run
      )

      return result if invalid_values.any? || dry_run

      migrated_values_count = already_migrated_count
      CustomField.transaction do
        custom_values_to_migrate.each do |custom_value|
          migrate_custom_value!(custom_value)
          migrated_values_count += 1
        end

        change_field_format!(custom_field, 'versioned_file')
      end

      result.migrated_values_count = migrated_values_count
      result
    end

    private

    def load_custom_field!
      super(
        expected_format: 'attachment',
        already_format: 'versioned_file',
        already_error_key: 'versioned_file_cf.tasks.migrate_file_custom_field.error_already_versioned_file',
        invalid_error_key: 'versioned_file_cf.tasks.migrate_file_custom_field.error_invalid_field_format'
      )
    end

    def assess_custom_value(custom_value)
      active_revision = VersionedFileCf::FileRevision.find_by(custom_value_id: custom_value.id, active: true)
      if active_revision
        return { status: :already_migrated } if already_migrated_value?(custom_value, active_revision)

        return invalid_result(
          custom_value,
          custom_value.value,
          I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.reason_already_migrated')
        )
      end

      if VersionedFileCf::FileRevision.exists?(custom_value_id: custom_value.id)
        return invalid_result(
          custom_value,
          custom_value.value,
          I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.reason_already_migrated')
        )
      end

      attachment_id = attachment_id_from(custom_value.value)
      unless attachment_id
        return invalid_result(
          custom_value,
          custom_value.value,
          I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.reason_attachment_id_invalid')
        )
      end

      attachment = Attachment.find_by(id: attachment_id)
      unless attachment
        return invalid_result(
          custom_value,
          attachment_id,
          I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.reason_attachment_missing')
        )
      end

      unless attachment.container == custom_value
        return invalid_result(
          custom_value,
          attachment.id,
          I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.reason_attachment_not_owned')
        )
      end

      return { status: :migratable } if attachment.readable? && attachment.is_text?

      invalid_result(
        custom_value,
        attachment.id,
        I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.reason_attachment_not_text')
      )
    end

    def already_migrated_value?(custom_value, active_revision)
      attachment_id = attachment_id_from(custom_value.value)
      return false unless attachment_id && active_revision.attachment_id == attachment_id

      attachment = Attachment.find_by(id: attachment_id)
      attachment && attachment.container == active_revision
    end

    def migrate_custom_value!(custom_value)
      attachment = Attachment.find(attachment_id_from(custom_value.value))
      timestamp = attachment.created_on || Time.current

      revision = VersionedFileCf::FileRevision.create!(
        custom_value: custom_value,
        attachment: attachment,
        author: attachment.author,
        filename: attachment.filename,
        content: read_text(attachment),
        revision_number: 1,
        active: true,
        created_at: timestamp,
        updated_at: timestamp
      )

      attachment.update!(container: revision)
    end
  end
end