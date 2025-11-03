#!/usr/bin/env python3
"""
Loomio File Uploads Sync to Google Drive
Syncs user-uploaded files to Google Drive for backup using Google Drive API
"""

import os
import sys
import json
import hashlib
from pathlib import Path
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError

# Configuration
GDRIVE_ENABLED = os.getenv('GDRIVE_ENABLED', 'false').lower() == 'true'
GDRIVE_CREDENTIALS = os.getenv('GDRIVE_CREDENTIALS')
GDRIVE_FOLDER_ID = os.getenv('GDRIVE_FOLDER_ID')

# Paths to sync
STORAGE_PATHS = [
    '/loomio/storage',
    '/loomio/public/system',
    '/loomio/public/files'
]

# Colors for output
BLUE = '\033[0;34m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
NC = '\033[0m'


def log(message):
    """Print message with color codes"""
    print(message, flush=True)


def get_drive_service():
    """Initialize Google Drive API service"""
    try:
        credentials_dict = json.loads(GDRIVE_CREDENTIALS)
        credentials = service_account.Credentials.from_service_account_info(
            credentials_dict,
            scopes=['https://www.googleapis.com/auth/drive.file']
        )
        service = build('drive', 'v3', credentials=credentials)
        return service
    except Exception as e:
        log(f"{RED}✗ Failed to initialize Google Drive API: {e}{NC}")
        return None


def find_or_create_folder(service, parent_id, folder_name):
    """Find or create a folder in Google Drive"""
    try:
        # Search for existing folder
        query = f"name='{folder_name}' and '{parent_id}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
        results = service.files().list(q=query, fields='files(id, name)').execute()
        folders = results.get('files', [])

        if folders:
            return folders[0]['id']

        # Create new folder
        folder_metadata = {
            'name': folder_name,
            'mimeType': 'application/vnd.google-apps.folder',
            'parents': [parent_id]
        }
        folder = service.files().create(body=folder_metadata, fields='id').execute()
        return folder['id']

    except HttpError as e:
        log(f"{RED}✗ Error with folder '{folder_name}': {e}{NC}")
        return None


def get_file_md5(file_path):
    """Calculate MD5 hash of file"""
    md5_hash = hashlib.md5()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            md5_hash.update(chunk)
    return md5_hash.hexdigest()


def file_exists_in_drive(service, parent_id, file_name, local_md5):
    """Check if file exists in Drive with same MD5"""
    try:
        query = f"name='{file_name}' and '{parent_id}' in parents and trashed=false"
        results = service.files().list(
            q=query,
            fields='files(id, name, md5Checksum)',
            pageSize=1
        ).execute()
        files = results.get('files', [])

        if files and files[0].get('md5Checksum') == local_md5:
            return files[0]['id']
        elif files:
            # File exists but different content - delete old version
            service.files().delete(fileId=files[0]['id']).execute()

        return None
    except HttpError:
        return None


def upload_file(service, parent_id, file_path):
    """Upload a single file to Google Drive"""
    try:
        file_name = file_path.name
        local_md5 = get_file_md5(file_path)

        # Check if file already exists with same content
        existing_id = file_exists_in_drive(service, parent_id, file_name, local_md5)
        if existing_id:
            return True  # Skip, already uploaded

        # Upload new file
        file_metadata = {
            'name': file_name,
            'parents': [parent_id]
        }
        media = MediaFileUpload(str(file_path), resumable=True)
        service.files().create(
            body=file_metadata,
            media_body=media,
            fields='id'
        ).execute()

        return True

    except Exception as e:
        log(f"{RED}  ✗ Failed to upload {file_name}: {e}{NC}")
        return False


def sync_directory(service, local_path, remote_parent_id):
    """Recursively sync a directory to Google Drive"""
    local_path = Path(local_path)

    if not local_path.exists():
        log(f"{YELLOW}⚠ Skipping non-existent path: {local_path}{NC}")
        return 0, 0

    total_files = 0
    uploaded_files = 0

    # Walk through directory
    for item in local_path.rglob('*'):
        if item.is_file():
            # Skip hidden files and temp files
            if item.name.startswith('.') or item.name.endswith('.tmp'):
                continue

            total_files += 1

            # Calculate relative path from local_path
            rel_path = item.relative_to(local_path)

            # Create folder structure in Drive
            current_parent = remote_parent_id
            for part in rel_path.parent.parts:
                current_parent = find_or_create_folder(service, current_parent, part)
                if not current_parent:
                    break

            if current_parent:
                if upload_file(service, current_parent, item):
                    uploaded_files += 1
                    if uploaded_files % 10 == 0:
                        log(f"  Uploaded {uploaded_files}/{total_files} files...")

    return total_files, uploaded_files


def main():
    """Main sync workflow"""
    # Check if Google Drive is enabled
    if not GDRIVE_ENABLED:
        log(f"{YELLOW}⚠ Google Drive sync is disabled (GDRIVE_ENABLED != true){NC}")
        log(f"{YELLOW}To enable: Set GDRIVE_ENABLED=true in .env{NC}")
        sys.exit(0)

    # Check required variables
    if not GDRIVE_CREDENTIALS or not GDRIVE_FOLDER_ID:
        log(f"{RED}✗ GDRIVE_CREDENTIALS or GDRIVE_FOLDER_ID not set{NC}")
        log(f"{YELLOW}Configure Google Drive settings in .env to enable file sync{NC}")
        sys.exit(1)

    log(f"{BLUE}Starting file upload sync to Google Drive...{NC}")

    # Initialize Drive API
    service = get_drive_service()
    if not service:
        sys.exit(1)

    # Find or create Upload folder
    upload_folder_id = find_or_create_folder(service, GDRIVE_FOLDER_ID, 'Upload')
    if not upload_folder_id:
        log(f"{RED}✗ Failed to create Upload folder{NC}")
        sys.exit(1)

    # Sync each path
    total_all = 0
    uploaded_all = 0

    for path in STORAGE_PATHS:
        folder_name = Path(path).name
        log(f"{BLUE}Syncing {path} → Upload/{folder_name}{NC}")

        # Find or create subfolder in Upload
        subfolder_id = find_or_create_folder(service, upload_folder_id, folder_name)
        if not subfolder_id:
            log(f"{RED}✗ Failed to create {folder_name} folder{NC}")
            continue

        # Sync directory
        total, uploaded = sync_directory(service, path, subfolder_id)
        total_all += total
        uploaded_all += uploaded

        log(f"{GREEN}✓ Synced {folder_name}: {uploaded}/{total} files{NC}")

    log(f"{GREEN}✓ File upload sync completed: {uploaded_all}/{total_all} files{NC}")


if __name__ == '__main__':
    main()
