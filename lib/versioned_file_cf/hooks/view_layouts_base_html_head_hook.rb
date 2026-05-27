module VersionedFileCf
  module Hooks
    class ViewLayoutsBaseHtmlHeadHook < Redmine::Hook::ViewListener
      def view_layouts_base_html_head(context = {})
        stylesheet_link_tag 'versioned_file_cf', plugin: 'redmine_versioned_file_cf'
      end
    end
  end
end
