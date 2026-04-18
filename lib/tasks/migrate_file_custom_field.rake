# frozen_string_literal: true

namespace :versioned_file_cf do
  desc 'Replace an existing file custom field with Versioned file'
  task migrate_file_custom_field: :environment do
    locale = (ENV['LOCALE'] || I18n.default_locale).to_sym

    I18n.with_locale(locale) do
      custom_field_id = ENV['ID'].presence
      abort I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.error_missing_custom_field_id') unless custom_field_id

      dry_run = ActiveModel::Type::Boolean.new.cast(ENV['DRY_RUN'])
      migrator = VersionedFileCf::FileCustomFieldMigrator.new(custom_field_id: custom_field_id, dry_run: dry_run)
      result = migrator.call

      puts I18n.t(
        'versioned_file_cf.tasks.migrate_file_custom_field.label_start',
        id: result.custom_field.id,
        name: result.custom_field.name,
        total: result.total_values_count,
        filled: result.filled_values_count
      )

      unless result.success?
        puts I18n.t(
          'versioned_file_cf.tasks.migrate_file_custom_field.label_invalid_header',
          count: result.invalid_values.count
        )

        result.invalid_values.each do |invalid_value|
          puts I18n.t(
            'versioned_file_cf.tasks.migrate_file_custom_field.label_invalid_value',
            custom_value_id: invalid_value.custom_value_id,
            customized_type: invalid_value.customized_type,
            customized_id: invalid_value.customized_id,
            attachment_id: invalid_value.attachment_id,
            reason: invalid_value.reason
          )
        end

        abort I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.error_aborted')
      end

      if dry_run
        puts I18n.t(
          'versioned_file_cf.tasks.migrate_file_custom_field.label_dry_run',
          count: result.filled_values_count
        )
      elsif result.filled_values_count.zero?
        puts I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.label_done_no_values')
      else
        puts I18n.t(
          'versioned_file_cf.tasks.migrate_file_custom_field.label_done',
          count: result.migrated_values_count
        )
      end
    end
  rescue VersionedFileCf::FileCustomFieldMigrator::MigrationError => e
    abort e.message
  end
end