# frozen_string_literal: true

module VersionedFileCf
  module Patches
    module CustomValuePatch
      def destroy
        self.class.transaction do
          destroy_versioned_files
          super
        end
      end

      private

      def destroy_versioned_files
        VersionedFileCf::FileRevision.includes(:attachment).where(custom_value_id: id).find_each(&:destroy)
      end
    end
  end
end
