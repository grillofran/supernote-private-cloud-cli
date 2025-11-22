# Supernote Private Cloud - CLI Upload Tool

A command-line tool for uploading documents to your [Supernote Private Cloud](https://supernote.com/pages/supernote-private-cloud) server. Upload files programmatically without using the web interface.

## Why This Exists

The Supernote Private Cloud web UI is great for manual uploads, but becomes tedious when you need to:

- Upload multiple files in batch
- Integrate uploads into automated workflows
- Script document management tasks
- Add files from remote servers or automation scripts

Simply copying files to the storage directory doesn't work - files must be registered in the database to appear in the UI and sync to devices. This tool handles both the file copy and database registration automatically.

## Features

- ✅ **Proper database registration** - Files appear in UI and sync to devices immediately
- ✅ **Directory auto-creation** - Creates folder paths if they don't exist
- ✅ **Duplicate detection** - Warns before overwriting existing files
- ✅ **Capacity tracking** - Updates storage usage automatically
- ✅ **Audit logging** - Maintains file action history
- ✅ **Zero dependencies** - Uses existing Docker containers

## Requirements

- **Linux only** (tested on Ubuntu/Debian, should work on other distributions)
- Supernote Private Cloud already installed and running
- Docker and Docker Compose
- Bash shell

## Installation

1. Download the script to your Supernote Private Cloud installation directory:

```bash
cd /path/to/your/supernote-private-cloud
wget https://raw.githubusercontent.com/YOUR_USERNAME/supernote-cli-upload/main/supernote-upload.sh
chmod +x supernote-upload.sh
```

2. That's it! The script reads credentials from your existing `.dbenv` file.

## Usage

### Basic Syntax

```bash
./supernote-upload.sh <email> <source_file> <destination_folder>
```

### Examples

**Upload a PDF to Document/Books:**
```bash
./supernote-upload.sh user@example.com ~/mybook.pdf Document/Books
```

**Upload a note to the Note folder:**
```bash
./supernote-upload.sh user@example.com ~/mynote.note Note
```

**Upload to a custom subfolder (creates if needed):**
```bash
./supernote-upload.sh user@example.com ~/report.pdf Document/Work/Reports
```

### Available Folders

- `Document/` - PDF and ebook files
- `Document/Books` - Books subfolder
- `Document/PDF` - PDFs subfolder
- `Note/` - Handwritten .note files
- `INBOX/` - Inbox folder
- `EXPORT/` - Exported files
- `SCREENSHOT/` - Screenshots

You can create any subfolder structure under these root folders.

## Batch Upload Example

Upload all PDFs from a directory:

```bash
#!/bin/bash
for file in ~/Downloads/*.pdf; do
    ./supernote-upload.sh user@example.com "$file" Document/Books
done
```

## How It Works

The script performs these operations:

1. **Validates** source file and looks up user ID from email
2. **Resolves directory path** in the database (follows Supernote's nested folder structure)
3. **Checks for duplicates** and prompts before overwriting
4. **Copies file** to the correct storage location
5. **Registers in database** with three operations:
   - Insert file record in `f_user_file` table
   - Update storage capacity in `f_capacity` table
   - Create audit log entry in `f_file_action` table

After upload, files appear immediately in the web UI and sync to connected Supernote devices.

## Technical Details

The Supernote Private Cloud uses a nested directory structure:
- Database root folders are uppercase: `DOCUMENT`, `NOTE`, `EXPORT`, etc.
- Physical filesystem uses mixed case: `Document/`, `Note/`, etc.
- Each folder is a record in the `f_user_file` table with `is_folder='Y'`
- Files must have both a physical file AND a database record to appear in UI

This script handles these complexities automatically.

## Contributing

Found a bug? Have a feature request? Open an issue or submit a pull request!

## License

MIT License - Use freely, modify as needed, no warranty provided.

## Acknowledgments

Built for the Supernote community. Thanks to Supernote for creating the Supernote Private Cloud solution.

---

**Note:** This is an unofficial community tool, not officially supported by Ratta/Supernote.
