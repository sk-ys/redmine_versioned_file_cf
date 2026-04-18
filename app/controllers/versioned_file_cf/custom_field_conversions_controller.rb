# frozen_string_literal: true

require 'cgi'

module VersionedFileCf
  class CustomFieldConversionsController < ApplicationController
    before_action :require_admin
    before_action :find_custom_field

    def convert_to_versioned_file
      result = VersionedFileCf::FileCustomFieldMigrator.new(custom_field_id: @custom_field.id).call
      flash[:notice] = migrate_notice(result)
    rescue VersionedFileCf::CustomFieldConversionBase::MigrationError => e
      flash[:error] = e.message
    else
      flash[:error] = invalid_values_message(result.invalid_values) unless result.success?
    ensure
      redirect_to edit_custom_field_path(@custom_field)
    end

    def convert_to_file
      result = VersionedFileCf::VersionedFileCustomFieldReverter.new(custom_field_id: @custom_field.id).call
      flash[:notice] = revert_notice(result)
    rescue VersionedFileCf::CustomFieldConversionBase::MigrationError => e
      flash[:error] = e.message
    else
      flash[:error] = invalid_values_message(result.invalid_values) unless result.success?
    ensure
      redirect_to edit_custom_field_path(@custom_field)
    end

    private

    def find_custom_field
      @custom_field = CustomField.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def migrate_notice(result)
      return if !result.success?
      return I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.label_done_no_values') if result.filled_values_count.zero?

      I18n.t('versioned_file_cf.tasks.migrate_file_custom_field.label_done', count: result.migrated_values_count)
    end

    def revert_notice(result)
      return if !result.success?
      return I18n.t('versioned_file_cf.tasks.revert_file_custom_field.label_done_no_values') if result.deleted_revisions_count.zero?

      I18n.t(
        'versioned_file_cf.tasks.revert_file_custom_field.label_done',
        count: result.migrated_values_count,
        revisions: result.deleted_revisions_count
      )
    end

    def invalid_values_message(invalid_values)
      lines = [I18n.t('versioned_file_cf.tasks.common.label_invalid_header', count: invalid_values.size)]
      invalid_values.first(5).each do |invalid_value|
        lines << I18n.t(
          'versioned_file_cf.tasks.common.label_invalid_value',
          custom_value_id: invalid_value.custom_value_id,
          customized_type: invalid_value.customized_type,
          customized_id: invalid_value.customized_id,
          attachment_id: invalid_value.attachment_id,
          reason: invalid_value.reason
        ).strip
      end

      remaining_count = invalid_values.size - 5
      if remaining_count.positive?
        lines << I18n.t('versioned_file_cf.ui.remaining_invalid_values', count: remaining_count)
      end

      lines.map { |line| CGI.escapeHTML(line) }.join('<br>').html_safe
    end
  end
end