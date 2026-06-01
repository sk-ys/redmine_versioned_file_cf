# frozen_string_literal: true

require_dependency 'redmine/string_array_diff/diff'
require 'open3'
require 'tempfile'

class VersionedFilesController < ApplicationController
  DIFF_TYPES = %w[inline sbs].freeze
  GIT_NO_INDEX_ARGS = %w[diff --no-index --no-color --text --].freeze

  before_action :find_revision, only: [:diff, :update_description, :destroy, :restore]
  before_action :find_custom_value, only: [:history, :compare]
  before_action :authorize_versioned_file_access

  helper :issues
  helper :attachments

  def history
    @version_count = revisions_scope.count
    @version_pages = Paginator.new(@version_count, per_page_option, params[:page])
    @revisions = revisions_scope.
      limit(@version_pages.per_page + 1).
      offset(@version_pages.offset).
      to_a
    @can_update_attachment_description = @revisions.any? && can_update_attachment_description?(@revisions.first)
  end

  def compare
    @revision = revisions_scope.find_by(id: params[:revision_id])
    @previous_revision = revisions_scope.find_by(id: params[:compare_to_id])
    render_404 and return unless @revision && @previous_revision

    if @previous_revision.revision_number > @revision.revision_number
      @revision, @previous_revision = @previous_revision, @revision
    end

    prepare_diff
    return if performed?
    return send_diff_data if diff_download_request?

    render :diff
  end

  def diff
    @previous_revision = if params[:compare_to_id].present?
                           VersionedFileCf::FileRevision.find_by(id: params[:compare_to_id], custom_value_id: @revision.custom_value_id)
                         else
                           @revision.previous_revision
                         end
    render_404 and return unless @previous_revision

    prepare_diff
    return if performed?
    return send_diff_data if diff_download_request?
  end

  def update_description
    return deny_access unless can_update_attachment_description?(@revision)

    if @revision.update_description(params[:description])
      render json: { success: true }
    else
      render json: { success: false, errors: @revision.attachment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    assign_contexts_from_revision
    if @revision.nil?
      respond_remove_revision_failure(
        l(:error_no_valid_revisions_selected_for_removal, scope: :versioned_file_cf)
      )
      return
    end

    unless @revision.visible?(User.current) && @revision.attachments_deletable?(User.current)
      respond_remove_revision_failure(
        l(:error_revision_cannot_be_deleted, scope: :versioned_file_cf),
        status: :forbidden
      )
      return
    end

    if @revision.active?
      respond_remove_revision_failure(
        l(:error_active_record_cannot_be_deleted, scope: :versioned_file_cf)
      )
      return
    end

    if @revision.destroy
      respond_remove_revision_success(l(:notice_revision_removed, scope: :versioned_file_cf))
    else
      message = @revision.errors.full_messages.to_sentence.presence ||
                l(:error_failed_to_remove_revision, scope: :versioned_file_cf)
      respond_remove_revision_failure(message)
    end
  end

  def restore
    assign_contexts_from_revision
    return deny_access unless can_restore_revision?(@revision)

    restored_revision = nil
    custom_value = @revision.custom_value
    issue = custom_value.customized if custom_value.customized.is_a?(Issue)

    VersionedFileCf::FileRevision.transaction do
      if issue
        unless issue.editable?(User.current)
          @restore_error_message = l(:error_issue_cannot_be_updated_for_restore, scope: :versioned_file_cf)
          raise ActiveRecord::Rollback
        end

        issue.init_journal(User.current)
        issue.current_journal.__send__(
          :add_custom_field_detail,
          custom_value.custom_field_id,
          custom_value.value,
          @revision.attachment_id.to_s
        )
        unless issue.save
          @restore_error_message = issue.errors.full_messages.to_sentence.presence ||
                                   l(:error_issue_cannot_be_updated_for_restore, scope: :versioned_file_cf)
          raise ActiveRecord::Rollback
        end
      end

      revisions_scope_for_custom_value(custom_value).current.update_all(active: false)
      next_revision_number = revisions_scope_for_custom_value(custom_value).maximum(:revision_number).to_i + 1
      restored_revision = VersionedFileCf::FileRevision.new(
        custom_value: custom_value,
        attachment_id: @revision.attachment_id,
        author: User.current,
        filename: @revision.filename,
        content: @revision.content,
        revision_number: next_revision_number,
        active: true
      )
      unless restored_revision.save
        @restore_error_message = restored_revision.errors.full_messages.to_sentence.presence ||
                                 l(:error_failed_to_restore_revision, scope: :versioned_file_cf)
        raise ActiveRecord::Rollback
      end

      custom_value.update_columns(value: @revision.attachment_id.to_s)
    end

    if restored_revision
      flash[:notice] = l(:notice_revision_restored, scope: :versioned_file_cf, revision: restored_revision.revision_number)
    else
      flash[:error] = @restore_error_message.presence || l(:error_failed_to_restore_revision, scope: :versioned_file_cf)
    end
    redirect_back_or_default history_versioned_files_path(custom_value_id: @custom_value.id)
  end

  private

  def prepare_diff
    assign_contexts_from_revision
    return deny_access unless @revision.visible?(User.current)

    @diff_type = resolve_diff_type
    persist_diff_type_preference(@diff_type)

    @diff_lines = diff_lines_for_display
    @diff = Redmine::UnifiedDiff.new(@diff_lines, type: @diff_type, max_lines: Setting.diff_max_lines_displayed.to_i)
    @diff_download_path = git_available? ? build_diff_download_path : nil
  end

  def assign_contexts_from_revision
    @attachment = @revision.attachment
    @custom_value = @revision.custom_value
    @custom_field = @custom_value.custom_field
  end

  def resolve_diff_type
    requested = params[:type].presence || User.current.pref[:diff_type] || 'inline'
    DIFF_TYPES.include?(requested) ? requested : 'inline'
  end

  def persist_diff_type_preference(diff_type)
    return unless User.current.logged?
    return if diff_type == User.current.pref[:diff_type]

    User.current.pref[:diff_type] = diff_type
    User.current.preference.save
  end

  def find_custom_value
    @custom_value = CustomValue.includes(:custom_field, :customized).find(params[:custom_value_id])
    @custom_field = @custom_value.custom_field
    if @custom_value.customized.is_a?(Issue)
      @issue = @custom_value.customized
      @project = @issue.project
      deny_access unless @issue.visible?(User.current)
    elsif @custom_value.customized.is_a?(TimeEntry)
      time_entry = @custom_value.customized
      @project = time_entry.project
      deny_access unless time_entry.visible?(User.current)
    elsif @custom_value.customized.is_a?(Project)
      @project = @custom_value.customized
      deny_access unless @project.visible?(User.current)
    elsif @custom_value.customized.is_a?(Version)
      version = @custom_value.customized
      @project = version.project
      deny_access unless version.visible?(User.current)
    elsif @custom_value.customized.is_a?(Document)
      document = @custom_value.customized
      @project = document.project
      deny_access unless document.visible?(User.current)
    elsif @custom_value.customized.is_a?(User)
      user = @custom_value.customized
      deny_access unless user.visible?(User.current)
    elsif @custom_value.customized.is_a?(Group)
      group = @custom_value.customized
      deny_access unless group.visible?(User.current)
    else
      render_404
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def revisions_scope
    VersionedFileCf::FileRevision.includes(:attachment, :author).
      where(custom_value_id: @custom_value.id).
      order(revision_number: :desc, id: :desc)
  end

  def find_revision
    @revision = VersionedFileCf::FileRevision.includes(:custom_value, :attachment, :author).find(params[:id])
    @project = @revision.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def can_update_attachment_description?(revision)
    return false unless revision&.visible?(User.current)
    return false unless revision.attachments_editable?(User.current)

    User.current.allowed_to?(:update_versioned_file_description, @project)
  end

  def can_restore_revision?(revision)
    return false if revision.nil? || revision.active?
    return false unless revision&.visible?(User.current)
    return false unless revision.attachments_visible?(User.current)

    User.current.allowed_to?(:restore_file_revision, @project)
  end

  def respond_remove_revision_success(message)
    respond_to do |format|
      format.json { render json: { success: true, message: message } }
      format.html do
        flash[:notice] = message
        redirect_back_or_default history_versioned_files_path(custom_value_id: @custom_value.id)
      end
    end
  end

  def respond_remove_revision_failure(message, status: :unprocessable_entity)
    respond_to do |format|
      format.json { render json: { success: false, message: message }, status: status }
      format.html do
        flash[:error] = message
        redirect_back_or_default history_versioned_files_path(custom_value_id: @custom_value.id)
      end
    end
  end

  def text_to_lines(text)
    text.to_s.lines(chomp: true)
  end

  def revisions_scope_for_custom_value(custom_value)
    VersionedFileCf::FileRevision.where(custom_value_id: custom_value.id)
  end

  def build_line_operations(previous_lines, current_lines)
    normalized_previous_lines = previous_lines.map { |line| normalize_line_for_matching(line) }
    normalized_current_lines = current_lines.map { |line| normalize_line_for_matching(line) }
    matches = Redmine::StringArrayDiff::Diff.lcs(normalized_previous_lines, normalized_current_lines)
    operations = []
    previous_index = 0
    current_index = 0

    while previous_index < matches.length
      current_match_index = matches[previous_index]
      if current_match_index
        while current_index < current_match_index
          operations << ['+', current_lines[current_index]]
          current_index += 1
        end
        if previous_lines[previous_index] == current_lines[current_match_index]
          operations << [' ', previous_lines[previous_index]]
        else
          operations << ['-', previous_lines[previous_index]]
          operations << ['+', current_lines[current_match_index]]
        end
        current_index += 1
      else
        operations << ['-', previous_lines[previous_index]]
      end
      previous_index += 1
    end

    while current_index < current_lines.length
      operations << ['+', current_lines[current_index]]
      current_index += 1
    end

    operations
  end

  def build_unified_diff(previous_revision, revision)
    previous_lines = text_to_lines(previous_revision.content.to_s)
    current_lines = text_to_lines(revision.content.to_s)
    operations = build_line_operations(previous_lines, current_lines)
    previous_name = diff_filename(previous_revision.filename)
    current_name = diff_filename(revision.filename)

    [
      "--- a/#{previous_name}",
      "+++ b/#{current_name}",
      "@@ -#{unified_range(previous_lines.length)} +#{unified_range(current_lines.length)} @@",
      *operations.map { |kind, line| "#{kind}#{line}" }
    ].join("\n")
  end

  def unified_range(count)
    start = count.zero? ? 0 : 1
    "#{start},#{count}"
  end

  def normalize_line_for_matching(line)
    line.to_s.strip
  end

  def diff_lines_for_display
    git_diff = build_git_no_index_diff(@previous_revision, @revision)
    return git_diff if git_diff.present?

    build_unified_diff(@previous_revision, @revision)
  end

  def build_git_no_index_diff(previous_revision, revision)
    return nil unless git_available?

    previous_file = nil
    current_file = nil

    begin
      previous_file = Tempfile.new(['versioned_file_prev', File.extname(previous_revision.filename.to_s)])
      current_file = Tempfile.new(['versioned_file_curr', File.extname(revision.filename.to_s)])
      previous_file.binmode
      current_file.binmode
      previous_file.write(previous_revision.content.to_s)
      current_file.write(revision.content.to_s)
      previous_file.flush
      current_file.flush

      stdout, _stderr, status = Open3.capture3(
        'git', *GIT_NO_INDEX_ARGS, previous_file.path, current_file.path
      )

      return nil unless [0, 1].include?(status.exitstatus)

      lines = stdout.lines
      return nil if lines.empty?

      normalize_git_diff_filenames(lines, previous_revision.filename.to_s, revision.filename.to_s)
    ensure
      previous_file&.close!
      current_file&.close!
    end
  rescue StandardError
    nil
  end

  def normalize_git_diff_filenames(lines, previous_name, current_name)
    previous_path = "a/#{diff_filename(previous_name)}"
    current_path = "b/#{diff_filename(current_name)}"
    normalized = lines.dup
    normalized.map! do |line|
      if line.start_with?('diff --git ')
        "diff --git #{quoted_diff_path(previous_path)} #{quoted_diff_path(current_path)}\n"
      elsif line.start_with?('--- ')
        "--- #{previous_path}\n"
      elsif line.start_with?('+++ ')
        "+++ #{current_path}\n"
      else
        line
      end
    end
    normalized
  end

  def diff_filename(name)
    File.basename(name.to_s).presence || 'versioned_file'
  end

  def quoted_diff_path(path)
    escaped = path.to_s.gsub('\\', '\\\\').gsub('"', '\\"')
    %("#{escaped}")
  end

  def git_available?
    return @git_available unless @git_available.nil?

    _out, _err, status = Open3.capture3('git', '--version')
    @git_available = status.success?
  rescue StandardError
    @git_available = false
  end

  def send_diff_data
    send_data Array(@diff_lines).join,
              filename: diff_download_filename,
              type: 'text/x-patch',
              disposition: 'attachment'
  end

  def diff_download_filename
    base = File.basename(@attachment.filename.to_s, File.extname(@attachment.filename.to_s)).presence || 'versioned_file'
    "#{base}_r#{@previous_revision.revision_number}_r#{@revision.revision_number}.diff"
  end

  def build_diff_download_path
    route_params = request.path_parameters.symbolize_keys.except(:format)
    query_params = request.query_parameters.except('type')
    url_for(route_params.merge(query_params).merge(format: :diff, only_path: true))
  end

  def diff_download_request?
    request.path_parameters[:format].to_s == 'diff' || params[:format].to_s == 'diff'
  end
end

def authorize_versioned_file_access
  if @project
    authorize
  else
    authorize_global
  end
end
