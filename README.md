# Redmine Versioned File CF Plugin

This plugin adds a new custom field format named `File (revision-managed)` to Redmine, allowing uploaded text files to be managed with revision history.

Japanese version: [README.ja.md](README.ja.md)

## Features

- Adds `File (revision-managed)` as a custom field format
- Supports file uploads in the same way as the existing file custom field
- Shows the history of uploaded files
- Shows diffs between revisions
- Lets you switch between `File` and `File (revision-managed)` using dedicated conversion buttons in the UI ([details](#ui-conversion-en))
- Provides rake tasks for orphan attachment cleanup and custom field format conversion ([details](#maintenance-en))

### Notes

- If the uploaded file is not a text file, diffs cannot be displayed.
- If Git is not available on the server, the standard Redmine file diff feature is used; if Git is available, the result of `git diff --no-index` is displayed.
- Git is required on the server to download diff files.

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

<a id="usage-en"></a>
## Usage

1. Create a new custom field from Administration (for any object such as Issue, Project, or Version).
2. Select `File (revision-managed)` as the format.
3. Configure allowed extensions if needed.
4. Upload a text file from the edit screen of each object.
5. A history list and diff links are shown at the bottom of the details page.

<a id="ui-conversion-en"></a>
### Converting Existing Custom Fields from the UI

The conversion button is shown only on the edit screen for custom fields of type `File` or `File (revision-managed)`.

- `File` -> `File (revision-managed)`: Converts the existing File custom field format to the revision-managed format.
- `File (revision-managed)` -> `File`: Converts back to the normal File custom field format.

When converting from `File (revision-managed)` to `File`, all revision history in the `vfcf_file_revisions` table and any past attachments are deleted, and only the latest file is kept as the normal File custom field attachment.

<a id="maintenance-en"></a>
## Maintenance

### Remove orphan attachments

If needed, you can remove orphan attachments whose container record has already been deleted by running the following from your Redmine root directory:

```shell
bundle exec rake versioned_file_cf:cleanup_orphan_attachments RAILS_ENV=production
```

#### Notes
- If there are no orphan records, the task prints a message and exits.
- If orphan records exist, the task deletes them and prints the deleted attachment IDs.

### Convert File to Versioned file

You can also replace an existing File custom field with the `File (revision-managed)` format by running the following from your Redmine root directory:

```shell
bundle exec rake versioned_file_cf:migrate_file_custom_field ID=12 RAILS_ENV=production
```

To check migratability without changing data:

```shell
bundle exec rake versioned_file_cf:migrate_file_custom_field ID=12 DRY_RUN=1 RAILS_ENV=production
```

#### Notes
- The migration task only targets custom fields whose format is the existing File custom field.
- If the existing File custom field has inconsistent attachments, the migration is aborted without making any changes.

### Convert Versioned file to File

You can also convert an existing `File (revision-managed)` custom field back to the normal `File` format, run the following from your Redmine root directory:

```shell
bundle exec rake versioned_file_cf:revert_file_custom_field ID=12 RAILS_ENV=production
```

To check revertability without changing data:

```shell
bundle exec rake versioned_file_cf:revert_file_custom_field ID=12 DRY_RUN=1 RAILS_ENV=production
```

#### Notes
- The revert task only targets custom fields whose format is `File (revision-managed)`.
- The revert task returns the latest file to a normal File custom field attachment and deletes all revision records and past attachments.


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