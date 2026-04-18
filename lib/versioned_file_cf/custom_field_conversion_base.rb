# frozen_string_literal: true

module VersionedFileCf
  class CustomFieldConversionBase
    MigrationError = Class.new(StandardError)

    InvalidValue = Struct.new(
      :custom_value_id,
      :customized_type,
      :customized_id,
      :attachment_id,
      :reason,
      keyword_init: true
    )

    def initialize(custom_field_id:, dry_run: false)
      @custom_field_id = custom_field_id
      @dry_run = dry_run
    end

    private

    attr_reader :dry_run

    def load_custom_field!(expected_format:, already_format:, already_error_key:, invalid_error_key:)
      custom_field = CustomField.find_by(id: @custom_field_id)
      raise MigrationError, I18n.t('versioned_file_cf.tasks.common.error_custom_field_not_found', id: @custom_field_id) unless custom_field

      if custom_field.field_format == already_format
        raise MigrationError, I18n.t(already_error_key, id: custom_field.id)
      end

      unless custom_field.field_format == expected_format
        raise MigrationError, I18n.t(
          invalid_error_key,
          id: custom_field.id,
          field_format: custom_field.field_format
        )
      end

      custom_field
    end

    def invalid_result(custom_value, attachment_id, reason)
      {
        status: :invalid,
        invalid_value: build_invalid_value(custom_value, attachment_id, reason)
      }
    end

    def build_invalid_value(custom_value, attachment_id, reason)
      InvalidValue.new(
        custom_value_id: custom_value.id,
        customized_type: custom_value.customized_type,
        customized_id: custom_value.customized_id,
        attachment_id: attachment_id,
        reason: reason
      )
    end

    def change_field_format!(custom_field, field_format)
      custom_field.update_columns(field_format: field_format)
      custom_field.reload
    end

    def attachment_id_from(value)
      string_value = value.to_s.strip
      return if string_value.blank? || string_value !~ /\A\d+\z/

      string_value.to_i
    end

    def read_text(attachment)
      content = File.binread(attachment.diskfile)
      content.force_encoding(Encoding::UTF_8)
      return content if content.valid_encoding?

      content.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
    end
  end
end