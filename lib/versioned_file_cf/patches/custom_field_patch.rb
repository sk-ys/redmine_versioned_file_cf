# frozen_string_literal: true

module VersionedFileCf
  module Patches
    module CustomFieldPatch
      extend ActiveSupport::Concern

      included do
        before_destroy :destroy_versioned_files_for_field
      end

      private

      def destroy_versioned_files_for_field
        VersionedFileCf::FileRevision.joins(:custom_value)
                            .where(custom_values: { custom_field_id: id })
                            .includes(:attachment)
                            .find_each(&:destroy)
      end
    end
  end
end
