# frozen_string_literal: true

module VersionedFileCf
  module Hooks
    class CustomFieldsFormHook < Redmine::Hook::ViewListener
      render_on :view_custom_fields_form_upper_box, partial: 'custom_fields/versioned_file_conversion_controls'
    end
  end
end