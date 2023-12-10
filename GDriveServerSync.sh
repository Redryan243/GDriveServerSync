#!/bin/bash

#####
# Modifiable Variables
#####
DATA_DIR="/path/to/directory/you/want/to/backup"			##Directory you want to backup
VERIFICATION_FILE="/path/to/directory/you/want/to/backup/file.txt"	##Choose a file that will be in your backed up folder, it's presence will be used to determine if backup ran 
BACKUP_NAME="name-you-want"						##Choose a name for your duplicacy backup


#####
#Variables below this should remain system generated.
#####
GCD_TOKEN="$DATA_DIR/.duplicacy/gcd-token.json"
LOG_FILE="$DATA_DIR/restore.log"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IN_CUSTOM_OPTIONS_MODE=false

# Functions for each command
function install_duplicacy() {
    local latest_version=$(curl -s https://api.github.com/repos/gilbertchen/duplicacy/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | cut -c 2-)
    wget "https://github.com/gilbertchen/duplicacy/releases/download/v${latest_version}/duplicacy_linux_x64_${latest_version}" -O duplicacy_linux_x64
    sudo mv duplicacy_linux_x64 /usr/local/bin/duplicacy
    sudo chmod 755 /usr/local/bin/duplicacy
    check_success "Duplicacy Installation"
}

function install_dependencies() {
    log_message "Starting installation of dependencies..."
    prepare_data_directory

    # Installing Expect and Duplicacy if not present
    if ! command -v expect &> /dev/null; then
        install_tool "expect" "sudo apt-get update && sudo apt-get install -y expect" "Expect Installation"
    else
        log_message "Expect is already installed."
    fi

    if ! command -v duplicacy &> /dev/null; then
        install_tool "duplicacy" "install_duplicacy" "Duplicacy Installation"
    else
        log_message "Duplicacy is already installed."
    fi

    log_message "All dependencies checked and installed."
}

function prepare_data_directory() {
    log_message "Preparing the data directory for restoration..."
    sudo chown -R $(whoami):$(whoami) "$DATA_DIR"  # Change ownership to current user
    sudo chmod -R u+rwX "$DATA_DIR"  # Set read/write permissions for the user
    check_success "Data directory prepared for restoration"
}

# Function to install a tool if it's not already installed
function install_tool() {
    local tool=$1
    local install_cmd=$2
    local success_msg=$3

    if ! command -v $tool &> /dev/null; then
        log_message "Installing $tool..."
        eval $install_cmd
        check_success "$success_msg"
    else
        log_message "$tool is already installed."
    fi
}

function authenticate_gdrive() {
    local DUPLICACY_DIR="${1:-$DATA_DIR/.duplicacy}"
    local GCD_TOKEN="${DUPLICACY_DIR}/gcd-token.json"
    local SCRIPT_DIR_TOKEN="${SCRIPT_DIR}/gcd-token.json"
    local DOWNLOADS_TOKEN="$HOME/Downloads/gcd-token.json"

    [ ! -d "$DUPLICACY_DIR" ] && mkdir -p "$DUPLICACY_DIR" && log_message "Duplicacy Directory Created"

    local max_attempts=3
    for attempt in $(seq 1 $max_attempts); do
        if [ -f "$GCD_TOKEN" ]; then
            log_message "Google Drive token file already at $GCD_TOKEN."
            check_success "Google Drive Authentication"
            break
        elif handle_gdrive_token "$SCRIPT_DIR_TOKEN" "$GCD_TOKEN" "false" || \
           handle_gdrive_token "$DOWNLOADS_TOKEN" "$GCD_TOKEN" "true"; then
            check_success "Google Drive Authentication"
            break
        elif [ $attempt -eq $max_attempts ]; then
            log_message "Error: Google Drive token file not found after multiple attempts."
            return 1
        else
            echo -e "\n\n\n"
            log_message "Google Drive token file not found. Please follow the instructions to obtain it."
            echo "1. Visit https://duplicacy.com/gcd_start to start the authorization process."
            echo "2. Follow the on-screen instructions to grant Duplicacy permission to access your Google Drive."
            echo "3. Download the generated token file."
            echo "4. Save the token file to one of the following locations: $GCD_TOKEN, $SCRIPT_DIR, or $HOME/Downloads"
            read -p "Press Enter after completing these steps..."
        fi
    done
}

function init_duplicacy() {
    local DUPLICACY_DIR="$DATA_DIR/.duplicacy"
    local CONFIG_FILE="$DUPLICACY_DIR/preferences"
    local TOKEN_DIR="$DUPLICACY_DIR/gcd-token.json"

    # Check if the Duplicacy repository is already initialized
    if [ -f "$CONFIG_FILE" ]; then
        log_message "Duplicacy repository already initialized at $DUPLICACY_DIR. If you are trying to restart, please delete this directory."
        return 0  # Return to the calling function
    fi

    log_message "Google Drive token is located at $TOKEN_DIR"

    # Change directory to DATA_DIR and initialize the Duplicacy repository
    cd "$DATA_DIR" || { log_message "Failed to change directory to $DATA_DIR"; return 1; }
    sudo -E DUPLICACY_GCD_TOKEN="$GCD_TOKEN" duplicacy init -e "$BACKUP_NAME" "gcd://$BACKUP_NAME"
    check_success "Repository Initialization"

    # Change ownership of the .duplicacy directory to the current user
    sudo chown -R "$(whoami):$(whoami)" "$DUPLICACY_DIR"
    check_success "Changed ownership of Duplicacy configuration to current user"

    log_message "Duplicacy repository initialization completed."
}

function restore_latest_revision() {
    # Verify the restoration and store the return status
    verify_restoration
    local verification_status=$?
    local proceed_with_restore="no"

    # If verification file exists, ask if user still wants to restore
    if [ $verification_status -eq 0 ]; then  # Check if verify_restoration returned 0 (file exists)
        read -p "Verification file exists. Do you still want to proceed with restoration (it will overwrite existing files)? (yes/no): " proceed_with_restore
        proceed_with_restore=$(echo $proceed_with_restore | tr '[:upper:]' '[:lower:]')  # Convert to lowercase
    fi

    # If file does not exist or user chooses to proceed
    if [ $verification_status -ne 0 ] || [[ "$proceed_with_restore" == "yes" || "$proceed_with_restore" == "y" ]]; then
        log_message "Proceeding with restoration..."

        # List all available revisions and find the latest revision
        log_message "Listing all available revisions for Duplicacy backup at $DATA_DIR..."
        cd "$DATA_DIR" || { log_message "Failed to change directory to $DATA_DIR"; return 1; }

        local latest_revision=$(sudo -E DUPLICACY_GCD_TOKEN="$GCD_TOKEN" duplicacy list | grep -oP "Snapshot ${BACKUP_NAME} revision \K\d+" | sort -nr | head -n1)
        check_success "Listed Available Revisions"

        if [ -z "$latest_revision" ]; then
            log_message "No revisions found. Exiting."
            return 1
        fi

        log_message "Latest revision found: $latest_revision"

        # Restore files from the latest revision
        log_message "Restoring files from the latest revision $latest_revision..."
        local restore_command="sudo -E DUPLICACY_GCD_TOKEN=\"$GCD_TOKEN\" duplicacy restore -r \"$latest_revision\""
        if [[ "$proceed_with_restore" == "yes" || "$proceed_with_restore" == "y" ]]; then
            restore_command+=" -overwrite"
        fi
        eval $restore_command
        check_success "Files Restored from Latest Revision $latest_revision"
    else
        log_message "Restoration skipped as per user's choice."
    fi
}

function verify_restoration() {
    if [ -f "$VERIFICATION_FILE" ]; then
        log_message "Verification successful: $VERIFICATION_FILE exists."
        return 0  # Indicates file exists
    else
        log_message "Verification failed: $VERIFICATION_FILE does not exist."
        return 1  # Indicates file does not exist
    fi
}

function backup() {
    log_message "Starting Duplicacy backup for $BACKUP_NAME..."
    cd "$DATA_DIR" || { log_message "Error: Failed to change directory to $DATA_DIR"; return 1; }

    # Perform backup using sudo and preserving environment variables
    sudo -E DUPLICACY_GCD_TOKEN="$GCD_TOKEN" duplicacy backup #-log -storage "$BACKUP_NAME"
    check_success "Duplicacy Backup for $BACKUP_NAME Completed"

    log_message "Backup operation for $BACKUP_NAME completed successfully."
}

function automate_backups() {
	echo "function not ready"
    # Placeholder for the automate_backups function
}

function init_server() {
	echo "function not ready"
    # Placeholder for the init_server function
}

# Function to run a given script
run_script() {
    echo "Running $1..."
    if ! $1; then
        echo "Warning: Script $1 failed."
    fi

    # Prompt for running another script only if in custom options mode
    if [ "$IN_CUSTOM_OPTIONS_MODE" = true ]; then
            enter_custom_options_mode
    fi
}

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE:-/path/to/default/logfile.log}"
}

# Function to check if the last command was successful
check_success() {
    if [ $? -eq 0 ]; then
        log_message "Success: $1"
    else
        log_message "Error: $1"
        return 1  # Return with error status instead of exiting the script
    fi
}

enter_custom_options_mode() {
    IN_CUSTOM_OPTIONS_MODE=true
    echo -e "\nPlease make a selection:"
    select option in install_dependencies authenticate_gdrive init_duplicacy restore_latest_revision backup automate_backups init_server "Exit Custom Mode"; do
        case $option in
            "Exit Custom Mode")
                IN_CUSTOM_OPTIONS_MODE=false
                return 0  # Return to the main loop
                ;;
            *)
                run_script $option
                ;;
        esac
    done
}

# Function to handle Google Drive token file
handle_gdrive_token() {
    local token_path="$1"
    local target_path="$2"
    local user_confirmation="$3"

    if [ -f "$token_path" ]; then
        if [ "$user_confirmation" == "true" ]; then
            read -p "Token file found at $token_path. Do you want to use it? [Y/n] " response
            case "$response" in
                [Yy]* ) ;;
                * ) return 1 ;;
            esac
        fi
        log_message "Google Drive token file found at $token_path. Moving to $target_path."
        cp "$token_path" "$target_path" && log_message "Token File Moved" || return 1
        return 0
    fi
    return 1
}

# Prompt for Encryption Password
prompt_for_password() {
    while true; do
        read -s -p "Enter Encryption Password: " ENCRYPTION_PASSWORD
        echo
        read -s -p "Verify Encryption Password: " ENCRYPTION_PASSWORD_VERIFY
        echo

        if [ "$ENCRYPTION_PASSWORD" = "$ENCRYPTION_PASSWORD_VERIFY" ]; then
            export DUPLICACY_PASSWORD=$ENCRYPTION_PASSWORD
            break
        else
            echo "Passwords do not match. Please try again."
        fi
    done
}

prompt_for_password

# Main Script Execution Loop
while true; do
    echo "Select the run mode:"
    echo "1. Full Restore  -First setup is not required"
    echo "2. First Setup"
    echo "3. Backup"
    echo "4. Basic Restore"
    echo "5. Custom Options"
    echo "6. Exit Script"
    read -p "Enter your choice (1, 2, 3, 4, 5, or 6): " choice

    case $choice in
        1)  # Full Restore Mode
            run_script install_dependencies
            run_script authenticate_gdrive
            run_script init_duplicacy
            run_script restore_latest_revision
            ;;
        2)  # First Setup
            run_script install_dependencies
            run_script authenticate_gdrive
            run_script init_duplicacy
            ;;
        3)  # Backup
            run_script backup
            ;;
        4)  # Overwrite Restore
            run_script restore_latest_revision
            ;;
        5)  # Custom Options Mode
            enter_custom_options_mode
            ;;
        6)  # Exit Script
            echo "Exiting script."
            exit 0
            ;;
        *)  # Invalid Choice
            echo "Invalid choice. Please try again."
            ;;
    esac
done
