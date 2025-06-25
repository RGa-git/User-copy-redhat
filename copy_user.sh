#!/bin/bash

# Script: copy_user.sh  
# Purpose: Copy user from source server to target server(s) on RedHat/AlmaLinux systems
# Author: RGa
# Date: 2025-06-25

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
VERBOSE=false
COPY_ACLS=true
SSH_KEY=""
SSH_PORT=22

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 -u USERNAME -s SOURCE_SERVER -t TARGET_SERVERS [OPTIONS]

Required:
  -u USERNAME         Username to copy
  -s SOURCE_SERVER    Source server hostname/IP
  -t TARGET_SERVERS   Target server(s) - comma separated for multiple

Options:
  -k SSH_KEY          Path to SSH private key (default: ~/.ssh/id_rsa)
  -p PORT             SSH port (default: 22)
  -d                  Dry run - show what would be done without executing
  -v                  Verbose output
  --no-acl            Skip copying ACLs (Access Control Lists)
  -h                  Show this help

Examples:
  $0 -u testuser -s test-server.local -t prod-server.local
  $0 -u developer -s dev.local -t "prod1.local,prod2.local" -d
  $0 -u admin -s source.local -t target.local -k ~/.ssh/custom_key -p 2222
  $0 -u webuser -s localhost -t "prod1,prod2,prod3" --no-acl -v

EOF
}

# Function to check if user exists on remote server
check_user_exists() {
    local server=$1
    local username=$2
    
    print_debug "Checking if user '$username' exists on $server"
    
    if simple_ssh "$server" "id $username" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to get user information from source server
get_user_info() {
    local server=$1
    local username=$2
    
    print_debug "Getting user information for '$username' from $server"
    
    # Check if we're on the local server
    if [ "$server" = "localhost" ] || [ "$server" = "$(hostname)" ] || [ "$server" = "$(hostname -f)" ]; then
        # Local commands
        USER_INFO=$(getent passwd $username 2>/dev/null)
        SHADOW_INFO=$(getent shadow $username 2>/dev/null)
        GROUP_INFO=$(groups $username 2>/dev/null)
    else        # Remote commands via SSH
        USER_INFO=$(simple_ssh "$server" "getent passwd $username" 2>/dev/null)
        SHADOW_INFO=$(simple_ssh "$server" "getent shadow $username" 2>/dev/null)
        GROUP_INFO=$(simple_ssh "$server" "groups $username" 2>/dev/null)
    fi
    
    if [ -z "$USER_INFO" ]; then
        print_error "User '$username' not found on source server $server"
        return 1
    fi
    
    return 0
}

# Function to create user on target server
create_user() {
    local server=$1
    local username=$2
    
    print_status "Creating user '$username' on $server"
    
    # Parse user info
    IFS=':' read -r user_name password uid gid gecos home shell <<< "$USER_INFO"
    
    # Parse shadow info for password hash
    IFS=':' read -r shadow_user password_hash rest <<< "$SHADOW_INFO"
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN: Would create user with following parameters:"
        echo "  Username: $user_name"
        echo "  UID: $uid"
        echo "  GID: $gid"
        echo "  Home: $home"
        echo "  Shell: $shell"
        echo "  GECOS: $gecos"
        return 0
    fi
    
    # Create user with specific UID and GID
    ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$server << EOF
        # Create group if it doesn't exist
        if ! getent group $gid >/dev/null 2>&1; then
            groupadd -g $gid $(echo "$GROUP_INFO" | cut -d':' -f1 | head -n1)
        fi
        
        # Create user
        useradd -u $uid -g $gid -d $home -s $shell -c "$gecos" $username
        
        # Set password hash if available
        if [ -n "$password_hash" ] && [ "$password_hash" != "!" ] && [ "$password_hash" != "*" ]; then
            usermod -p '$password_hash' $username
        fi
EOF
    
    if [ $? -eq 0 ]; then
        print_status "User '$username' created successfully on $server"
    else
        print_error "Failed to create user '$username' on $server"
        return 1
    fi
}

# Function to copy home directory
copy_home_directory() {
    local source_server=$1
    local target_server=$2
    local username=$3
    
    print_status "Copying home directory for '$username' from $source_server to $target_server"
    
    # Get home directory path
    home_dir=$(echo "$USER_INFO" | cut -d':' -f6)
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN: Would copy $home_dir from $source_server to $target_server"
        return 0
    fi
    
    # Create home directory if it doesn't exist
    ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "mkdir -p $home_dir"
    
    # Copy home directory - check if source is local
    if [ "$source_server" = "localhost" ] || [ "$source_server" = "$(hostname)" ] || [ "$source_server" = "$(hostname -f)" ]; then
        # Local to remote copy
        cd $home_dir && tar czf - . | ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "cd $home_dir && tar xzf -"
    else
        # Remote to remote copy
        ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$source_server "cd $home_dir && tar czf - ." | \
        ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "cd $home_dir && tar xzf -"
    fi
      if [ $? -eq 0 ]; then
        # Fix ownership
        uid=$(echo "$USER_INFO" | cut -d':' -f3)
        gid=$(echo "$USER_INFO" | cut -d':' -f4)
        ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "chown -R $uid:$gid $home_dir"
          # Copy ACLs if available and enabled
        if [ "$COPY_ACLS" = true ]; then
            copy_acls "$source_server" "$target_server" "$home_dir"
        fi
        
        print_status "Home directory copied successfully"
    else
        print_error "Failed to copy home directory"
        return 1
    fi
}

# Function to copy SSH keys
copy_ssh_keys() {
    local source_server=$1
    local target_server=$2
    local username=$3
    
    home_dir=$(echo "$USER_INFO" | cut -d':' -f6)
    ssh_dir="$home_dir/.ssh"
    
    print_debug "Checking for SSH keys in $ssh_dir"
    
    # Check if .ssh directory exists on source
    if [ "$source_server" = "localhost" ] || [ "$source_server" = "$(hostname)" ] || [ "$source_server" = "$(hostname -f)" ]; then
        # Local check
        if [ ! -d $ssh_dir ]; then
            print_debug "No .ssh directory found for user '$username'"
            return 0
        fi
    else
        # Remote check
        if ! ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$source_server "[ -d $ssh_dir ]" 2>/dev/null; then
            print_debug "No .ssh directory found for user '$username'"
            return 0
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN: Would copy SSH keys from $ssh_dir"
        return 0
    fi
    
    print_status "Copying SSH keys for '$username'"
    
    # Copy .ssh directory
    if [ "$source_server" = "localhost" ] || [ "$source_server" = "$(hostname)" ] || [ "$source_server" = "$(hostname -f)" ]; then
        # Local to remote copy
        cd $ssh_dir && tar czf - . | ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "mkdir -p $ssh_dir && cd $ssh_dir && tar xzf -"
    else
        # Remote to remote copy
        ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$source_server "cd $ssh_dir && tar czf - ." | \
        ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "mkdir -p $ssh_dir && cd $ssh_dir && tar xzf -"
    fi
    
    # Set correct permissions
    uid=$(echo "$USER_INFO" | cut -d':' -f3)
    gid=$(echo "$USER_INFO" | cut -d':' -f4)
    ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server << EOF
        chown -R $uid:$gid $ssh_dir
        chmod 700 $ssh_dir
        chmod 600 $ssh_dir/* 2>/dev/null || true
        chmod 644 $ssh_dir/*.pub 2>/dev/null || true
EOF
    
    print_status "SSH keys copied successfully"
}

# Function to add user to groups
add_to_groups() {
    local server=$1
    local username=$2
    
    print_status "Adding user '$username' to groups on $server"
    
    # Parse groups (remove username: prefix)
    groups=$(echo "$GROUP_INFO" | sed "s/^$username : //")
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN: Would add user to groups: $groups"
        return 0
    fi
    
    # Add user to each group
    for group in $groups; do
        if [ "$group" != "$username" ]; then  # Skip primary group
            print_debug "Adding user to group: $group"
            ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$server "usermod -a -G $group $username" 2>/dev/null
        fi
    done
    
    print_status "User added to groups successfully"
}

# Function to copy user to target server
copy_user_to_server() {
    local source_server=$1
    local target_server=$2
    local username=$3
    
    print_status "Starting user copy: $username from $source_server to $target_server"
    
    # Check if target server is reachable
    if ! ssh -o ConnectTimeout=10 -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "echo 'Connection test'" >/dev/null 2>&1; then
        print_error "Cannot connect to target server: $target_server"
        return 1
    fi
    
    # Check if user already exists on target
    if check_user_exists "$target_server" "$username"; then
        print_warning "User '$username' already exists on $target_server"
        read -p "Overwrite existing user? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping $target_server"
            return 0
        fi
        
        # Delete existing user
        if [ "$DRY_RUN" = false ]; then
            ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "userdel -r $username" 2>/dev/null || true
        fi
    fi
    
    # Create user
    if ! create_user "$target_server" "$username"; then
        return 1
    fi
    
    # Copy home directory
    if ! copy_home_directory "$source_server" "$target_server" "$username"; then
        print_warning "Home directory copy failed, but continuing..."
    fi
    
    # Copy SSH keys
    if ! copy_ssh_keys "$source_server" "$target_server" "$username"; then
        print_warning "SSH keys copy failed, but continuing..."
    fi
    
    # Add to groups
    if ! add_to_groups "$target_server" "$username"; then
        print_warning "Group assignment failed, but continuing..."
    fi
    
    print_status "User '$username' successfully copied to $target_server"
    return 0
}

# Function to copy ACLs (Access Control Lists)
copy_acls() {
    local source_server=$1
    local target_server=$2
    local path=$3
    
    print_debug "Copying ACLs for path: $path"
    
    # Check if ACL tools are available on both servers
    local acl_available=true
    
    if [ "$source_server" = "localhost" ] || [ "$source_server" = "$(hostname)" ] || [ "$source_server" = "$(hostname -f)" ]; then
        # Check local server
        if ! command -v getfacl >/dev/null 2>&1; then
            acl_available=false
        fi
    else
        # Check remote source server
        if ! ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$source_server "command -v getfacl" >/dev/null 2>&1; then
            acl_available=false
        fi
    fi
    
    # Check target server
    if ! ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "command -v setfacl" >/dev/null 2>&1; then
        acl_available=false
    fi
    
    if [ "$acl_available" = false ]; then
        print_warning "ACL tools not available on all servers - skipping ACL copy"
        return 0
    fi
    
    print_status "Copying ACLs for $path"
    
    # Get ACLs from source and apply to target
    if [ "$source_server" = "localhost" ] || [ "$source_server" = "$(hostname)" ] || [ "$source_server" = "$(hostname -f)" ]; then
        # Local source - get ACLs and send to target
        getfacl -R "$path" 2>/dev/null | ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "setfacl --restore=-" 2>/dev/null
    else
        # Remote source - get ACLs via SSH and send to target
        ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$source_server "getfacl -R '$path'" 2>/dev/null | \
        ssh -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$target_server "setfacl --restore=-" 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        print_status "ACLs copied successfully"
    else
        print_warning "ACL copy failed, but continuing..."
    fi
}

# Simple SSH function - just plain SSH
simple_ssh() {
    local server=$1
    shift
    local command="$*"
    
    if [ "$server" = "localhost" ] || [ "$server" = "$(hostname)" ] || [ "$server" = "$(hostname -f)" ]; then
        # Local execution
        eval "$command"
    else
        # Remote execution - just plain SSH
        ssh -o StrictHostKeyChecking=no -p $SSH_PORT ${SSH_KEY:+-i $SSH_KEY} root@$server "$command"
    fi
}

# Simple function to prompt for password once
prompt_for_password() {
    if [ -z "$SSH_KEY" ] || [ ! -f "$SSH_KEY" ]; then
        print_status "No SSH key found. You'll need to enter the root password."
        print_warning "IMPORTANT: You'll be asked for the password several times during execution."
        print_warning "This is normal - just enter the same password each time."
        echo -n "Press Enter to continue or Ctrl+C to cancel..."
        read
    fi
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--username)
                USERNAME="$2"
                shift 2
                ;;
            -s|--source)
                SOURCE_SERVER="$2"
                shift 2
                ;;
            -t|--target)
                TARGET_SERVERS="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --no-acl)
                COPY_ACLS=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check required parameters
    if [ -z "$USERNAME" ] || [ -z "$SOURCE_SERVER" ] || [ -z "$TARGET_SERVERS" ]; then
        print_error "Missing required parameters"
        show_usage
        exit 1
    fi
    
    # Set default SSH key if not specified
    if [ -z "$SSH_KEY" ] && [ -f ~/.ssh/id_rsa ]; then
        SSH_KEY=~/.ssh/id_rsa
    fi
    
    print_status "Starting user copy operation"
    print_status "Username: $USERNAME"
    print_status "Source: $SOURCE_SERVER"
    print_status "Target(s): $TARGET_SERVERS"
      if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi
      # Warn user about password prompts
    prompt_for_password
      # Check source server connectivity (skip if source is localhost)
    if [ "$SOURCE_SERVER" != "localhost" ] && [ "$SOURCE_SERVER" != "$(hostname)" ] && [ "$SOURCE_SERVER" != "$(hostname -f)" ]; then
        if ! simple_ssh "$SOURCE_SERVER" "echo 'Connection test'" >/dev/null 2>&1; then
            print_error "Cannot connect to source server: $SOURCE_SERVER"
            exit 1
        fi
    fi
    
    # Get user information from source server
    if ! get_user_info "$SOURCE_SERVER" "$USERNAME"; then
        exit 1
    fi
    
    print_debug "User info retrieved successfully"
    
    # Convert comma-separated target servers to array
    IFS=',' read -ra TARGET_ARRAY <<< "$TARGET_SERVERS"
    
    # Copy user to each target server
    for target in "${TARGET_ARRAY[@]}"; do
        # Trim whitespace
        target=$(echo "$target" | xargs)
        
        if ! copy_user_to_server "$SOURCE_SERVER" "$target" "$USERNAME"; then
            print_error "Failed to copy user to $target"
            continue
        fi
    done
    
    print_status "User copy operation completed"
}

# Run main function with all arguments
main "$@"
