# frozen_string_literal: true

namespace :versioned_file_cf do
  desc 'Clean up orphan attachments for deleted VersionedFileCf::FileRevision records'
  task cleanup_orphan_attachments: :environment do
    locale = (ENV['LOCALE'] || I18n.default_locale).to_sym

    I18n.with_locale(locale) do
      orphans = Attachment
        .where(container_type: 'VersionedFileCf::FileRevision')
        .where.not(container_id: VersionedFileCf::FileRevision.select(:id))

      count = orphans.count
      if count.zero?
        puts I18n.t('versioned_file_cf.tasks.cleanup_orphan_attachments.label_none')
        next
      end

      puts I18n.t('versioned_file_cf.tasks.cleanup_orphan_attachments.label_start', count: count)
      destroyed = 0
      orphans.find_each do |attachment|
        attachment.destroy
        destroyed += 1
        puts I18n.t(
          'versioned_file_cf.tasks.cleanup_orphan_attachments.label_deleted',
          id: attachment.id,
          disk_filename: attachment.disk_filename
        )
      end

      puts I18n.t('versioned_file_cf.tasks.cleanup_orphan_attachments.label_done', count: destroyed)
    end
  end
end
