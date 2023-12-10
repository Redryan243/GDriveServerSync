# GDriveServerSync
"This CLI tool automates server data backup and restoration using Duplicacy CLI to Google Drive. It's designed for efficient and straightforward data management, ensuring safe and accessible backups."
# GDriveServerSync

GDriveServerSync is a script designed for automating data backups and restores using Duplicacy CLI, to Google Drive. It simplifies the process of setting up Duplicacy for use with Google Drive and offers various functionalities for data backup and restoration. It currently has limited commands, but it will likely be expanding. 

## Features

- **Automates installation**: Automatically installs the necessary tools and prepares the environment for Duplicacy.
- **Google Drive Authentication**: Helps with the authentication process with Google Drive to facilitate backups.
- **Backup/Restore**: Performs backup/restore of a specified directory.

## Prerequisites

Before using GDriveServerSync, ensure that you have the following:

- Linux
- Sudo privileges for certain operations.
- A Google Drive account for storing backups.

## Installation

To use the script, follow these steps:

1. **Clone the Repository**: Clone or download the script to your local system.

2. **Set Execute Permissions**: Ensure that the script has execute permissions using the following command:
   ```bash
   chmod +x GDriveServerSync.sh

3. **Set variables**: 3 variables must be set in the text of the script. Open it with a text editor and update them.

4. **Run script**: Run the from terminal with ./GDriveServerSync and follow the prompts.
