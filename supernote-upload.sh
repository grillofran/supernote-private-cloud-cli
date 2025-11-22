#!/bin/bash
#
# Supernote Private Cloud - CLI Document Upload Tool
#
# This script allows you to upload documents to your Supernote private cloud from the command line.
# It properly registers files in the database so they appear in the UI and sync to devices.
#
# Usage:
#     ./supernote-upload.sh <email> <source_file> <destination_folder>
#
# Example:
#     ./supernote-upload.sh user@example.com ~/mybook.pdf Document/Books
#     ./supernote-upload.sh user@example.com ~/mynote.note Note/MyNotes
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load database credentials
if [ ! -f "$SCRIPT_DIR/.dbenv" ]; then
    echo -e "${RED}Error: .dbenv file not found${NC}"
    exit 1
fi

source "$SCRIPT_DIR/.dbenv"

# Storage base path
STORAGE_BASE="$SCRIPT_DIR/supernote_data"

# Function to execute MySQL query
mysql_exec() {
    docker exec mariadb mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -h 127.0.0.1 -D "$MYSQL_DATABASE" -se "$1" 2>&1 | grep -v "Warning"
}

# Function to generate a unique ID (simplified snowflake-like)
generate_id() {
    echo $(($(date +%s%N) / 1000000))
}

# Function to calculate MD5
calculate_md5() {
    md5sum "$1" | awk '{print $1}'
}

# Function to get file size
get_file_size() {
    stat -c%s "$1"
}

# Function to get user ID
get_user_id() {
    local email="$1"
    local user_id=$(mysql_exec "SELECT user_id FROM u_user WHERE email = '$email'")

    if [ -z "$user_id" ]; then
        echo -e "${RED}Error: User with email '$email' not found${NC}"
        exit 1
    fi

    echo "$user_id"
}

# Function to ensure directory exists in database
ensure_directory() {
    local user_id="$1"
    local dir_path="$2"
    local storage_path="$3"

    if [ -z "$dir_path" ] || [ "$dir_path" = "." ] || [ "$dir_path" = "/" ]; then
        echo "0"
        return
    fi

    # Split path and process each component
    local parent_id=0
    local IFS='/'
    local i=0
    local current_path=""

    for part in $dir_path; do
        [ -z "$part" ] && continue

        # Map common folder names
        local search_name="$part"
        local actual_name="$part"

        # Special handling for root folders - they have uppercase DB names but mixed case subfolders
        if [ $i -eq 0 ]; then
            case "$part" in
                Document)
                    # First create DOCUMENT root
                    search_name="DOCUMENT"
                    local root_id=$(mysql_exec "SELECT id FROM f_user_file WHERE user_id = $user_id AND directory_id = 0 AND file_name = 'DOCUMENT' AND is_folder = 'Y' AND is_active = 'Y'")
                    if [ -z "$root_id" ]; then
                        echo -e "${RED}Error: DOCUMENT root folder not found in database${NC}"
                        exit 1
                    fi
                    # Now create the Document subfolder under DOCUMENT
                    parent_id=$root_id
                    search_name="Document"
                    actual_name="Document"
                    ;;
                Note)
                    # First create NOTE root
                    search_name="NOTE"
                    local root_id=$(mysql_exec "SELECT id FROM f_user_file WHERE user_id = $user_id AND directory_id = 0 AND file_name = 'NOTE' AND is_folder = 'Y' AND is_active = 'Y'")
                    if [ -z "$root_id" ]; then
                        echo -e "${RED}Error: NOTE root folder not found in database${NC}"
                        exit 1
                    fi
                    # Now create the Note subfolder under NOTE
                    parent_id=$root_id
                    search_name="Note"
                    actual_name="Note"
                    ;;
                EXPORT|SCREENSHOT|INBOX)
                    # These don't have subfolders, keep as-is
                    ;;
            esac
        fi

        # Check if directory exists
        local dir_id=$(mysql_exec "SELECT id FROM f_user_file WHERE user_id = $user_id AND directory_id = $parent_id AND file_name = '$search_name' AND is_folder = 'Y' AND is_active = 'Y'")

        if [ -z "$dir_id" ]; then
            # Create directory
            dir_id=$(generate_id)
            local now=$(date '+%Y-%m-%d %H:%M:%S')

            mysql_exec "INSERT INTO f_user_file (id, user_id, directory_id, file_name, is_folder, size, is_active, create_time, update_time, terminal_file_edit_time) VALUES ($dir_id, $user_id, $parent_id, '$search_name', 'Y', 0, 'Y', '$now', '$now', 0)"

            # Create physical directory
            if [ -z "$current_path" ]; then
                current_path="$actual_name"
            else
                current_path="$current_path/$actual_name"
            fi
            local phys_dir="$storage_path/$current_path"
            mkdir -p "$phys_dir"
            echo -e "${GREEN}  Created directory: $search_name${NC}"
        else
            if [ -z "$current_path" ]; then
                current_path="$actual_name"
            else
                current_path="$current_path/$actual_name"
            fi
        fi

        parent_id=$dir_id
        ((i++))
    done

    echo "$parent_id"
}

# Function to upload file
upload_file() {
    local email="$1"
    local source_file="$2"
    local dest_folder="$3"

    # Validate source file
    if [ ! -f "$source_file" ]; then
        echo -e "${RED}Error: Source file '$source_file' does not exist${NC}"
        exit 1
    fi

    # Get user information
    local user_id=$(get_user_id "$email")
    echo -e "${GREEN}Found user: $email (ID: $user_id)${NC}"

    # Determine storage path
    local user_storage="$STORAGE_BASE/$email/Supernote"
    if [ ! -d "$user_storage" ]; then
        echo -e "${RED}Error: User storage directory does not exist: $user_storage${NC}"
        exit 1
    fi

    # Ensure destination directory exists
    echo "Ensuring destination path exists: $dest_folder"
    local directory_id=$(ensure_directory "$user_id" "$dest_folder" "$user_storage")

    # Calculate file properties
    local file_name=$(basename "$source_file")
    local file_size=$(get_file_size "$source_file")
    local file_md5=$(calculate_md5 "$source_file")

    # Check if file already exists
    local existing=$(mysql_exec "SELECT id FROM f_user_file WHERE user_id = $user_id AND directory_id = $directory_id AND file_name = '$file_name' AND is_active = 'Y'")

    if [ -n "$existing" ]; then
        echo -e "${YELLOW}Warning: File '$file_name' already exists in '$dest_folder'${NC}"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Upload cancelled"
            exit 0
        fi

        # Mark old file as inactive
        local now=$(date '+%Y-%m-%d %H:%M:%S')
        mysql_exec "UPDATE f_user_file SET is_active = 'N', update_time = '$now' WHERE user_id = $user_id AND directory_id = $directory_id AND file_name = '$file_name'"
    fi

    # Copy file to destination
    local dest_path="$user_storage/$dest_folder/$file_name"
    mkdir -p "$(dirname "$dest_path")"
    cp "$source_file" "$dest_path"
    echo -e "${GREEN}Copied file to: $dest_path${NC}"

    # Register file in database
    local file_id=$(generate_id)
    local now=$(date '+%Y-%m-%d %H:%M:%S')
    local terminal_edit_time=$(($(stat -c%Y "$source_file") * 1000))

    mysql_exec "INSERT INTO f_user_file (id, user_id, directory_id, file_name, inner_name, size, md5, is_folder, is_active, create_time, update_time, terminal_file_edit_time) VALUES ($file_id, $user_id, $directory_id, '$file_name', NULL, $file_size, '$file_md5', 'N', 'Y', '$now', '$now', $terminal_edit_time)"

    # Update user capacity
    mysql_exec "INSERT INTO f_capacity (user_id, used_capacity, total_capacity, create_time, update_time) VALUES ($user_id, $file_size, 107374182400, '$now', '$now') ON DUPLICATE KEY UPDATE used_capacity = used_capacity + $file_size, update_time = '$now'"

    # Log the action
    local action_id=$(generate_id)
    mysql_exec "INSERT INTO f_file_action (id, user_id, file_id, file_name, path, md5, is_folder, size, action, create_time, update_time) VALUES ($action_id, $user_id, $file_id, '$file_name', '$dest_folder', '$file_md5', 'N', $file_size, 'A', '$now', '$now')"

    echo ""
    echo -e "${GREEN}✓ Successfully uploaded '$file_name'${NC}"
    echo "  Size: $file_size bytes"
    echo "  MD5: $file_md5"
    echo "  Location: $dest_folder/$file_name"
    echo "  Database ID: $file_id"
    echo ""
    echo "The file should now be visible in the web UI and will sync to your devices."
}

# Main
if [ $# -ne 3 ]; then
    echo "Supernote Private Cloud - CLI Document Upload Tool"
    echo ""
    echo "Usage: $0 <email> <source_file> <destination_folder>"
    echo ""
    echo "Examples:"
    echo "  $0 user@example.com ~/mybook.pdf Document/Books"
    echo "  $0 user@example.com ~/mynote.note Note/MyNotes"
    echo ""
    echo "Available folders:"
    echo "  Document/         - PDF and ebook files"
    echo "  Document/Books    - Books"
    echo "  Document/PDF      - PDFs"
    echo "  Note/             - Handwritten notes"
    echo "  INBOX/            - Inbox"
    echo "  EXPORT/           - Exported files"
    echo ""
    exit 1
fi

upload_file "$1" "$2" "${3%/}"
