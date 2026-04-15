# frozen_string_literal: true

module VersionedFileCf
  module Patches
    module CustomValuePatch
      extend ActiveSupport::Concern

      included do
        before_destroy :destroy_versioned_files
      end

      private

      def destroy_versioned_files
        VersionedFileCf::FileRevision.includes(:attachment).where(custom_value_id: id).find_each(&:destroy)
      end
    end
  end
end
