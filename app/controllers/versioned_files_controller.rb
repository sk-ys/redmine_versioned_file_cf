# frozen_string_literal: true

require_dependency 'redmine/string_array_diff/diff'
require 'open3'
require 'tempfile'

class VersionedFilesController < ApplicationController
  DIFF_TYPES = %w[inline sbs].freeze
  GIT_NO_INDEX_ARGS = %w[diff --no-index --no-color --text --].freeze

  before_action :find_revision, only: [:diff]
  before_action :find_custom_value, only: [:history, :compare]

  helper :issues
  helper :attachments

  def history
    @version_count = revisions_scope.count
    @version_pages = Paginator.new(@version_count, per_page_option, params[:page])
    @revisions = revisions_scope.
      limit(@version_pages.per_page + 1).
      offset(@version_pages.offset).
      to_a
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
    @revision = VersionedFileCf::FileRevision.find(params[:id])
    @revision.update_description(params[:description])
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false }, status: :not_found
  end

  private

  def prepare_diff
    assign_diff_context
    return deny_access unless @revision.visible?(User.current)

    @diff_type = resolve_diff_type
    persist_diff_type_preference(@diff_type)

    @diff_lines = diff_lines_for_display
    @diff = Redmine::UnifiedDiff.new(@diff_lines, type: @diff_type, max_lines: Setting.diff_max_lines_displayed.to_i)
    @diff_download_path = git_available? ? build_diff_download_path : nil
  end

  def assign_diff_context
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
      @project = @issue.project if @issue.respond_to?(:project)
      deny_access unless @issue.visible?(User.current)
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
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def text_to_lines(text)
    text.to_s.lines(chomp: true)
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
