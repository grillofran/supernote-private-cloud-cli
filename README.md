# Supernote Private Cloud - CLI Upload Tool

## Overview

Supernote Private Cloud is **completely self-hosted** with no runtime dependencies on external servers. This repository contains a CLI tool for programmatically uploading files while maintaining database consistency.

## CLI Upload Tool

### Interactive Usage

```bash
./supernote-upload.sh <email> <source_file> <destination_folder>

# Examples
./supernote-upload.sh user@example.com ~/book.pdf Document/Books
./supernote-upload.sh user@example.com ~/note.note Note/MyNotes
```

### Programmatic Usage (Python/automation)

```bash
./supernote-upload.sh --force --no-color <email> <source_file> <destination_folder>
```

**Flags:**
- `--force` / `-f` - Auto-overwrite existing files without prompting
- `--no-color` / `-n` - Disable ANSI color codes for clean output
- `--help` / `-h` - Show usage information

**Python Integration:**
```python
import subprocess

result = subprocess.run([
    "./supernote-upload.sh",
    "--force", "--no-color",
    "user@example.com",
    "/path/to/file.pdf",
    "Document/PDF/Folder"
], capture_output=True, text=True, timeout=60)

if result.returncode == 0:
    print("Success!")
```

### How It Works

1. Validates source file and user
2. Creates destination directory structure (if needed)
3. Copies file to `supernote_data/{email}/Supernote/{folder}/`
4. Registers file in database with metadata (MD5, size, timestamps)
5. Updates user capacity and logs action

Files appear immediately in the web UI and sync to devices.

### Available Destinations

- `Document/` - PDFs, ebooks (subfolders: Books, PDF, etc.)
- `Note/` - Handwritten .note files
- `INBOX/`, `EXPORT/`, `SCREENSHOT/` - Standard folders

### Database Schema

Files require both filesystem presence and database records in `f_user_file`:
- Root folders: `DOCUMENT`, `NOTE`, `EXPORT`, `INBOX`, `SCREENSHOT` (uppercase in DB)
- Physical paths: `Document/`, `Note/`, etc. (mixed case)
- Hierarchy maintained via `directory_id` parent links
