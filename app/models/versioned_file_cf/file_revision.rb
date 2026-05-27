# frozen_string_literal: true
module VersionedFileCf
  class VersionedFileCf::FileRevision < ApplicationRecord
    self.table_name = 'vfcf_file_revisions'

    belongs_to :custom_value
    belongs_to :attachment
    belongs_to :author, class_name: 'User', optional: true

    scope :current, -> { where(active: true) }

    validates :revision_number, presence: true
    validates :filename, presence: true

    delegate :custom_field, :customized, to: :custom_value

    after_destroy :destroy_attachment

    def issue
      customized if customized.is_a?(Issue)
    end

    def project
      return customized if customized.is_a?(Project)
      return customized.project if customized.respond_to?(:project)
    end

    def previous_revision
      self.class.where(custom_value_id: custom_value_id)
                .where('revision_number < ?', revision_number)
                .order(revision_number: :desc, id: :desc)
                .first
    end

    def visible?(user = User.current)
      return custom_value.attachments_visible?(user) if custom_value.respond_to?(:attachments_visible?)
      return customized.visible?(user) if customized.respond_to?(:visible?)

      false
    end

    def attachments_visible?(user = User.current)
      visible?(user)
    end

    def attachments_editable?(user = User.current)
      return false unless visible?(user)
      return false if custom_value.respond_to?(:editable?) && !custom_value.editable?
      return customized.editable?(user) if customized.respond_to?(:editable?)
      return customized.attachments_editable?(user) if customized.respond_to?(:attachments_editable?)

      true
    end

    def attachments_deletable?(user = User.current)
      attachments_editable?(user)
    end

    def update_description(new_description)
      attachment.update(description: new_description.to_s)
    end

    private

    def destroy_attachment
      attachment&.destroy
    end
  end
end
