module VersionedFileHelper
  def title_from_customized(customized)
    case customized
    when TimeEntry
      "#{l(:label_spent_time)} ##{customized.id}"
    when Document
      "#{l(:label_document)}: #{customized.title}"
    else
      customized.to_s
    end
  end
end