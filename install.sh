#!/bin/bash

# Debian Auto Upgrade - One-click Installation Script
# Author: everett7623
# Repository: https://github.com/everett7623/debian-auto-upgrade

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Project information
REPO_URL="https://github.com/everett7623/debian-auto-upgrade"
RAW_URL="https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main"
SCRIPT_NAME="debian_upgrade.sh"
INSTALL_DIR="/"
SYMLINK_NAME="debian-upgrade"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. This installer will install the script system-wide."
        USE_SUDO=""
    else
        if command -v sudo >/dev/null 2>&1; then
            USE_SUDO="sudo"
        else
            log_error "This script requires sudo privileges or root access."
            exit 1
        fi
    fi
}

# Check system compatibility
check_system() {
    log_info "Checking system compatibility..."
    
    if ! grep -q "^ID=debian" /etc/os-release 2>/dev/null; then
        log_error "This tool is designed for Debian systems only."
        exit 1
    fi
    
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        log_error "Either wget or curl is required for installation."
        log_info "Please install one of them: apt update && apt install wget"
        exit 1
    fi
    
    log_success "System compatibility check passed."
}

# Download the main script
download_script() {
    local temp_file="/tmp/${SCRIPT_NAME}"
    local download_url="${RAW_URL}/${SCRIPT_NAME}"
    
    log_info "Downloading Debian Auto Upgrade script..."
    log_info "Download URL: $download_url"
    
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$download_url" -o "$temp_file"; then
            log_error "Failed to download script using curl."
            log_error "URL: $download_url"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q "$download_url" -O "$temp_file"; then
            log_error "Failed to download script using wget."
            log_error "URL: $download_url"
            return 1
        fi
    fi
    
    # Verify the downloaded file
    if [[ ! -f "$temp_file" ]] || [[ ! -s "$temp_file" ]]; then
        log_error "Downloaded file is empty or does not exist."
        return 1
    fi
    
    # Check if it's a valid bash script
    if ! head -n 1 "$temp_file" | grep -q "^#!/bin/bash"; then
        log_error "Downloaded file is not a valid bash script."
        log_error "First line: $(head -n 1 "$temp_file")"
        return 1
    fi
    
    log_success "Script downloaded successfully."
    echo "$temp_file"
}

# Install the script
install_script() {
    local temp_file="$1"
    local target_file="${INSTALL_DIR}/${SCRIPT_NAME}"
    
    log_info "Installing script to ${target_file}..."
    
    # Create install directory if it doesn't exist
    $USE_SUDO mkdir -p "$INSTALL_DIR"
    
    # Copy script to install directory
    $USE_SUDO cp "$temp_file" "$target_file"
    
    # Make executable
    $USE_SUDO chmod +x "$target_file"
    
    # Create symlink for easier access
    if [[ -L "${INSTALL_DIR}/${SYMLINK_NAME}" ]]; then
        $USE_SUDO rm "${INSTALL_DIR}/${SYMLINK_NAME}"
    fi
    $USE_SUDO ln -s "$target_file" "${INSTALL_DIR}/${SYMLINK_NAME}"
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    log_success "Script installed successfully!"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    if [[ -x "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
        log_success "Installation verified: ${INSTALL_DIR}/${SCRIPT_NAME}"
    else
        log_error "Installation verification failed."
        return 1
    fi
    
    if [[ -L "${INSTALL_DIR}/${SYMLINK_NAME}" ]]; then
        log_success "Symlink created: ${INSTALL_DIR}/${SYMLINK_NAME}"
    else
        log_warning "Symlink creation failed."
    fi
    
    # Check if install directory is in PATH
    if echo "$PATH" | grep -q "$INSTALL_DIR"; then
        log_success "Installation directory is in PATH."
    else
        log_warning "Installation directory is not in PATH."
        log_info "You may need to add ${INSTALL_DIR} to your PATH or use full path."
    fi
    
    # Test script execution
    log_info "Testing script execution..."
    if timeout 10 "${INSTALL_DIR}/${SCRIPT_NAME}" --version >/dev/null 2>&1; then
        log_success "Script execution test passed."
    else
        log_warning "Script execution test failed or timed out."
        log_info "This may be normal if the script requires interactive input."
    fi
}

# Display usage information
show_usage() {
    cat << EOF

${GREEN}========================================${NC}
${GREEN}  Debian Auto Upgrade - Installed!${NC}
${GREEN}========================================${NC}

${BLUE}Usage:${NC}
  ${SCRIPT_NAME}                    # Run the upgrade
  ${SYMLINK_NAME}                   # Same as above (symlink)
  ${SCRIPT_NAME} --check            # Check for available upgrades
  ${SCRIPT_NAME} --help             # Show help information

${BLUE}Examples:${NC}
  # Basic upgrade
  sudo ${SCRIPT_NAME}
  
  # Check what upgrades are available
  ${SCRIPT_NAME} --check
  
  # Debug mode
  ${SCRIPT_NAME} --debug
  
  # Fix system issues only
  ${SCRIPT_NAME} --fix-only

${BLUE}Important Notes:${NC}
  • Always backup your system before upgrading
  • For VPS users, ensure console access is available
  • The upgrade process may take significant time
  • Internet connection is required throughout the process

${BLUE}Documentation:${NC}
  Repository: ${REPO_URL}
  Issues: ${REPO_URL}/issues
  
${BLUE}Support:${NC}
  Email: everett7623@gmail.com

EOF
}

# Main installation function
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Debian Auto Upgrade - Installer${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    log_info "Starting installation process..."
    
    check_root
    check_system
    
    local temp_file
    temp_file=$(download_script)
    
    if [[ $? -eq 0 && -n "$temp_file" ]]; then
        install_script "$temp_file"
        verify_installation
        show_usage
        
        echo
        log_success "Installation completed successfully!"
        log_info "You can now run '${SCRIPT_NAME}' or '${SYMLINK_NAME}' to start upgrading your Debian system."
    else
        log_error "Installation failed during download process."
        log_info "Please check your internet connection and try again."
        log_info "If the problem persists, you can manually download and install:"
        echo
        echo "  wget ${RAW_URL}/${SCRIPT_NAME}"
        echo "  chmod +x ${SCRIPT_NAME}"
        echo "  sudo mv ${SCRIPT_NAME} ${INSTALL_DIR}/"
        echo
        exit 1
    fi
}

# Run main function
main "$@"
