# frozen_string_literal: true

module VersionedFileCf
  module Patches
    module CustomizablePatch
      def store_attachment_custom_value_ids
        super
        @versioned_file_custom_value_ids = custom_values.select { |cv| cv.custom_field.field_format == 'versioned_file' }
                                                     .map(&:id)
        @versioned_file_attachment_ids = if @versioned_file_custom_value_ids.present?
                                          VersionedFileCf::FileRevision.where(custom_value_id: @versioned_file_custom_value_ids).pluck(:attachment_id)
                                        else
                                          []
                                        end
      end

      def destroy_custom_value_attachments
        destroy_versioned_file_attachments
        super
      end

      private

      def destroy_versioned_file_attachments
        return if @versioned_file_attachment_ids.blank?

        Attachment.where(id: @versioned_file_attachment_ids).find_each(&:destroy)
      end
    end
  end
end
