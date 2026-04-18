# Redmine Versioned File CF Plugin

This plugin adds a new custom field format named `File (revision-managed)` to Redmine, allowing uploaded text files to be managed with revision history.

Japanese version: [README.ja.md](README.ja.md)

## Features

- Adds `File (revision-managed)` as a custom field format
- Supports file uploads in the same way as the existing file custom field
- Shows the history of uploaded files
- Shows diffs between revisions

### Notes

- This plugin assumes uploaded files are text files
- Git must be available on the server to download diff files

## Installation

### 1. Download
#### Using Git
```shell
cd your_redmine/plugins
git clone https://github.com/sk-ys/redmine_versioned_file_cf.git
```

#### Without Git
1. Download from one of the following links:
   - Release version: https://github.com/sk-ys/redmine_versioned_file_cf/releases
   - Latest version: https://github.com/sk-ys/redmine_versioned_file_cf/archive/refs/heads/main.zip
2. Extract it into the `plugins` folder with the folder name `redmine_versioned_file_cf`

### 2. Migration
Run the following from your Redmine root directory:

```shell
bundle exec rake redmine:plugins:migrate NAME=redmine_versioned_file_cf RAILS_ENV=production
```

### 3. Restart Redmine
Restart Redmine.

## Usage

1. Create a new custom field from Administration (choose any object such as Issue, Project, or Version).
2. Select `File (revision-managed)` as the format.
3. Configure allowed extensions if needed.
4. Upload a text file from the edit screen of each object.
5. A history list and diff links are shown at the bottom of the details page.

### Converting Existing Custom Fields from the UI

On the custom field edit screen, this plugin adds a conversion button only for `File` and `File (revision-managed)` formats.

- `File` -> `File (revision-managed)`: converts the existing file custom field to the revision-managed format.
- `File (revision-managed)` -> `File`: converts the field back to the normal file format.

When converting from `File (revision-managed)` to `File`, all revision history stored in `vfcf_file_revisions` is deleted. The current file is kept as the normal file custom field attachment.

## Testing

Prepare the test database from your Redmine root directory:

```shell
bundle exec rails db:test:prepare RAILS_ENV=test
bundle exec rake redmine:plugins:migrate NAME=redmine_versioned_file_cf RAILS_ENV=test
```

Run the plugin tests:

```shell
bundle exec rails test plugins/redmine_versioned_file_cf/test RAILS_ENV=test
```

Notes:

- If you encounter a minitest / SimpleCov loading issue, add `MT_NO_PLUGINS=1` at the beginning of the command.

## Maintenance

If needed, you can remove orphan attachments whose container record has already been deleted.

Run the following from your Redmine root directory:

```shell
bundle exec rake versioned_file_cf:cleanup_orphan_attachments RAILS_ENV=production
```

You can also replace an existing file custom field with Versioned file.

Run the following from your Redmine root directory:

```shell
bundle exec rake versioned_file_cf:migrate_file_custom_field ID=12 RAILS_ENV=production
```

To check migratability without changing data:

```shell
bundle exec rake versioned_file_cf:migrate_file_custom_field ID=12 DRY_RUN=1 RAILS_ENV=production
```

You can also replace an existing Versioned file custom field with File. The current file is preserved and the revision history in `vfcf_file_revisions` is deleted.

Run the following from your Redmine root directory:

```shell
bundle exec rake versioned_file_cf:revert_file_custom_field ID=12 RAILS_ENV=production
```

To check revertability without changing data:

```shell
bundle exec rake versioned_file_cf:revert_file_custom_field ID=12 DRY_RUN=1 RAILS_ENV=production
```

Behavior:

- If there are no orphan records, it prints a message and exits.
- If orphan records exist, it deletes them and prints the deleted attachment IDs.
- The migration task only targets custom fields whose format is the existing file custom field.
- If any attached value is not a text file or has inconsistent attachment data, the migration is aborted without applying changes.
- The revert task only targets custom fields whose format is Versioned file.
- The revert task keeps the current file as a normal file custom field attachment and deletes all revision history records.