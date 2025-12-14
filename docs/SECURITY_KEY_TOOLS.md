# Security Key Tools Guide

**Date**: December 11, 2024
**Status**: ✅ Complete
**Coverage**: 12 essential tools across YubiKey, FIDO2, U2F, and other hardware keys

## Executive Summary

Comprehensive hardware security key support has been added to the package profiles, with focus on:

- **YubiKey** (most popular hardware key)
- **FIDO2/U2F** standard protocols
- **SoloKeys** and **Nitrokey** alternatives

**Total Tools Added**: 12 packages covering all major use cases.

## Quick Start

### Install YubiKey Essentials

```bash
# Core YubiKey management
rsr pkg install yubikey-manager

# PIV (smart card) support
rsr pkg install yubico-piv-tool

# FIDO2 support
rsr pkg install libfido2
```

### Install Complete Security Keys Suite

```bash
# Install all security key tools
rsr pkg install secrets.security-keys
```

### Verify YubiKey Detection

```bash
# Check YubiKey is detected
ykman list

# Show YubiKey info
ykman info
```

## Tools Overview

### 🔑 YubiKey Core Tools (5 packages)

| Tool | Type | Description | Priority |
|------|------|-------------|----------|
| **yubikey-manager** (ykman) | CLI | Primary configuration tool | ⭐⭐⭐ Essential |
| **yubico-piv-tool** | CLI | PIV/smart card management | ⭐⭐⭐ Essential |
| **yubikey-personalization** | CLI | Legacy OTP configuration | ⭐⭐ Recommended |
| **yubikey-manager-qt** | GUI | Graphical YubiKey Manager | ⭐⭐ Recommended |
| **yubioath-desktop** | GUI | TOTP/HOTP authenticator | ⭐⭐ Recommended |

### 🔐 FIDO2/U2F Tools (4 packages)

| Tool | Type | Description | Priority |
|------|------|-------------|----------|
| **libfido2** | Library | FIDO2 protocol library | ⭐⭐⭐ Essential |
| **fido2-tools** | CLI | FIDO2 testing utilities | ⭐⭐ Recommended |
| **pam-u2f** | System | U2F system authentication | ⭐⭐ Recommended |
| **libu2f-host** | Library | U2F host library | ⭐ Optional |

### 🔒 Integration & Other Keys (3 packages)

| Tool | Type | Description | Priority |
|------|------|-------------|----------|
| **age-plugin-yubikey** | Plugin | Age encryption with YubiKey | ⭐⭐ Recommended |
| **solo-tools** | CLI | SoloKeys management | ⭐ Optional |
| **nitrokey-app** | GUI | Nitrokey management | ⭐ Optional |

## Package Details

### 1. yubikey-manager (ykman)

**Primary YubiKey configuration tool.**

```yaml
- name: yubikey-manager
  description: YubiKey Manager CLI (ykman) - configure all YubiKey features
  brew: ykman
  winget: Yubico.YubikeyManager
  apt: yubikey-manager
  dnf: yubikey-manager
  pacman: yubikey-manager
```

**Features**:

- Configure all YubiKey applications (OTP, FIDO2, PIV, OATH)
- Manage PINs and credentials
- Enable/disable interfaces
- Firmware updates

**Usage Examples**:

```bash
# List connected YubiKeys
ykman list

# Show device info
ykman info

# Configure FIDO2
ykman fido fingerprints list
ykman fido info

# Manage OATH credentials (TOTP/HOTP)
ykman oath accounts list
ykman oath accounts add "GitHub:user@example.com"
ykman oath accounts code "GitHub:user@example.com"

# PIV operations
ykman piv certificates list
ykman piv keys generate 9a key.pem
```

**Platform Support**:

- ✅ macOS (Homebrew)
- ✅ Linux (all major distros)
- ✅ Windows (winget)

---

### 2. yubico-piv-tool

**YubiKey PIV (smart card) management.**

```yaml
- name: yubico-piv-tool
  description: YubiKey PIV (smart card) management tool
  brew: yubico-piv-tool
  apt: yubico-piv-tool
  dnf: yubico-piv-tool
  pacman: yubico-piv-tool
```

**Features**:

- Manage PIV certificates
- Generate and import keys
- Sign and decrypt data
- SSH authentication with PIV

**Usage Examples**:

```bash
# Check PIV status
yubico-piv-tool -a status

# Generate key in slot 9a (authentication)
yubico-piv-tool -a generate -s 9a -o public.pem

# Create self-signed certificate
yubico-piv-tool -a verify-pin -a selfsign-certificate \
  -s 9a -S "/CN=YubiKey PIV/" -i public.pem -o cert.pem

# Import certificate
yubico-piv-tool -a import-certificate -s 9a -i cert.pem

# Use with SSH
yubico-piv-tool -a export-certificate -s 9a -o - | \
  ssh-keygen -i -m PKCS8 -f /dev/stdin > yubikey.pub
```

**PIV Slots**:

- **9a**: PIV Authentication (SSH, login)
- **9c**: Digital Signature (signing)
- **9d**: Key Management (encryption)
- **9e**: Card Authentication

---

### 3. yubikey-personalization

**Legacy YubiKey OTP configuration.**

```yaml
- name: yubikey-personalization
  description: YubiKey personalization tool (legacy OTP configuration)
  brew: yubikey-personalization
  apt: yubikey-personalization
  dnf: yubikey-personalization-gui
  pacman: yubikey-personalization
```

**Features**:

- Configure OTP slots
- Set static passwords
- Challenge-response (HMAC-SHA1)

**Usage Examples**:

```bash
# Program slot 1 with Yubico OTP
ykpersonalize -1

# Program slot 2 with static password
ykpersonalize -2 -ostatic-ticket -ostrong-pw1=6

# Configure challenge-response
ykpersonalize -2 -ochal-resp -ochal-hmac -ohmac-lt64 -oserial-api-visible
```

**Note**: For modern YubiKeys, use `ykman` instead. This is for legacy compatibility.

---

### 4. yubikey-manager-qt

**GUI for YubiKey Manager.**

```yaml
- name: yubikey-manager-qt
  description: YubiKey Manager GUI application
  brew: --cask yubico-yubikey-manager
  apt: yubikey-manager-qt
  dnf: yubikey-manager-qt
  pacman: yubikey-manager-qt
  flatpak: com.yubico.yubioath
```

**Features**:

- Graphical interface for ykman
- Visual configuration
- Easy credential management
- Firmware updates

**Best For**:

- Users who prefer GUIs
- Initial setup
- Quick device info

---

### 5. yubioath-desktop

**YubiKey Authenticator for TOTP/HOTP codes.**

```yaml
- name: yubioath-desktop
  description: YubiKey Authenticator - TOTP/HOTP credential manager
  brew: --cask yubico-authenticator
  flatpak: com.yubico.yubioath
```

**Features**:

- Store TOTP/HOTP codes on YubiKey
- Touch-required 2FA
- QR code scanning
- Backup codes

**Usage**:

- Scan QR codes from websites
- Generate 2FA codes with YubiKey touch
- Offline 2FA (no phone needed)

**Benefits**:

- Hardware-protected 2FA secrets
- No phone dependency
- Touch-to-auth security

---

### 6. libfido2

**FIDO2 protocol library.**

```yaml
- name: libfido2
  description: FIDO2 library for communication with authenticators
  brew: libfido2
  apt: libfido2-1
  dnf: libfido2
  pacman: libfido2
  apk: libfido2
```

**Features**:

- FIDO2/WebAuthn protocol support
- Required dependency for many tools
- USB HID communication

**Required By**:

- OpenSSH 8.2+ (FIDO2 keys)
- Browsers (WebAuthn)
- Various CLI tools

---

### 7. fido2-tools

**FIDO2 command-line utilities.**

```yaml
- name: fido2-tools
  description: FIDO2 command-line tools (fido2-token, fido2-cred, fido2-assert)
  apt: fido2-tools
  dnf: fido2-tools
  pacman: libfido2
```

**Tools Included**:

- **fido2-token**: List and manage FIDO2 tokens
- **fido2-cred**: Create FIDO2 credentials
- **fido2-assert**: Test authentication

**Usage Examples**:

```bash
# List FIDO2 devices
fido2-token -L

# Get device info
fido2-token -I /dev/hidraw0

# Create credential
fido2-cred -M -h -r example.com /dev/hidraw0

# Test assertion
fido2-assert -G -h example.com /dev/hidraw0
```

---

### 8. pam-u2f

**U2F authentication for Linux login/sudo.**

```yaml
- name: pam-u2f
  description: PAM module for U2F authentication
  brew: pam-u2f
  apt: libpam-u2f
  dnf: pam-u2f
  pacman: pam-u2f
```

**Features**:

- U2F for system login
- U2F for sudo
- Multi-key support
- Fallback mechanisms

**Setup**:

```bash
# Create U2F keys directory
mkdir -p ~/.config/Yubico

# Register YubiKey
pamu2fcfg > ~/.config/Yubico/u2f_keys

# Register additional YubiKey (backup)
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys

# Configure PAM (edit /etc/pam.d/sudo)
# Add: auth sufficient pam_u2f.so
```

**Security Benefits**:

- Hardware-backed authentication
- Phishing-resistant
- Backup keys supported

---

### 9. age-plugin-yubikey

**Age encryption with YubiKey PIV.**

```yaml
- name: age-plugin-yubikey
  description: Age encryption plugin for YubiKey PIV
  brew: age-plugin-yubikey
  cargo: age-plugin-yubikey
```

**Features**:

- Hardware-protected age encryption
- Uses YubiKey PIV slots
- PIN-protected decryption

**Usage Examples**:

```bash
# List PIV keys
age-plugin-yubikey --list

# Generate recipient (public key)
age-plugin-yubikey --identity

# Encrypt file
age -r age1yubikey1... secret.txt > secret.txt.age

# Decrypt file (requires YubiKey + PIN)
age -d -i age-yubikey-identity.txt secret.txt.age > secret.txt
```

**Use Cases**:

- Encrypted backups
- Secret storage
- Secure file sharing

---

### 10. solo-tools

**SoloKeys management (open-source FIDO2).**

```yaml
- name: solo-tools
  description: SoloKeys management CLI (open-source FIDO2 key)
  brew: solo2-cli
  pip: solo1
```

**Features**:

- Configure SoloKeys
- Firmware updates
- Key management

**Usage**:

```bash
# List Solo devices
solo2 ls

# Get device info
solo2 info

# Update firmware
solo2 update
```

---

### 11. nitrokey-app

**Nitrokey management application.**

```yaml
- name: nitrokey-app
  description: Nitrokey management application
  apt: nitrokey-app
  dnf: nitrokey-app
  flatpak: com.nitrokey.nitrokey-app
```

**Features**:

- Nitrokey Pro/Storage management
- OTP configuration
- Password safe

---

## Common Use Cases

### 1. SSH Authentication with YubiKey

**Option A: FIDO2 SSH Keys (OpenSSH 8.2+)**

```bash
# Generate FIDO2 SSH key
ssh-keygen -t ed25519-sk -O resident -O verify-required

# The key is stored ON the YubiKey
# Requires touch for each use

# Copy to server
ssh-copy-id -i ~/.ssh/id_ed25519_sk.pub user@server

# Use (will require YubiKey touch)
ssh user@server
```

**Option B: PIV SSH Keys**

```bash
# Generate PIV key on YubiKey
yubico-piv-tool -a generate -s 9a -o public.pem

# Create certificate
yubico-piv-tool -a verify-pin -a selfsign-certificate \
  -s 9a -S "/CN=SSH Key/" -i public.pem -o cert.pem

# Import certificate
yubico-piv-tool -a import-certificate -s 9a -i cert.pem

# Export public key for SSH
yubico-piv-tool -a export-certificate -s 9a -o - | \
  ssh-keygen -i -m PKCS8 -f /dev/stdin > ~/.ssh/yubikey.pub

# Copy to server
ssh-copy-id -i ~/.ssh/yubikey.pub user@server

# Configure SSH to use YubiKey (add to ~/.ssh/config)
PKCS11Provider /usr/local/lib/libykcs11.dylib  # macOS
# PKCS11Provider /usr/lib/x86_64-linux-gnu/libykcs11.so  # Linux
```

### 2. Two-Factor Authentication (2FA)

**Store TOTP codes on YubiKey:**

```bash
# Add GitHub 2FA to YubiKey
ykman oath accounts add "GitHub:username" -o TOTP

# Generate code (requires touch)
ykman oath accounts code "GitHub:username"

# Or use GUI
yubioath-desktop
```

**Benefits**:

- No phone needed
- Hardware-protected secrets
- Touch-required security

### 3. System Login with U2F

```bash
# Install PAM module
sudo apt install libpam-u2f  # Debian/Ubuntu
sudo dnf install pam-u2f     # Fedora

# Register YubiKey
mkdir -p ~/.config/Yubico
pamu2fcfg > ~/.config/Yubico/u2f_keys

# Register backup key
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys

# Configure sudo (edit /etc/pam.d/sudo)
sudo nano /etc/pam.d/sudo
# Add after @include common-auth:
# auth sufficient pam_u2f.so

# Test
sudo ls  # Should prompt for YubiKey touch
```

### 4. Age Encryption with YubiKey

```bash
# Install age and plugin
brew install age age-plugin-yubikey  # macOS
apt install age                       # Linux (+ cargo install age-plugin-yubikey)

# Generate identity
age-plugin-yubikey --generate

# Encrypt file
age -r age1yubikey1... secret.txt > secret.txt.age

# Decrypt (requires PIN + YubiKey)
age -d -i age-yubikey-identity.txt secret.txt.age
```

### 5. GPG with YubiKey (OpenPGP Card)

```bash
# Check card status
gpg --card-status

# Generate keys on card
gpg --edit-card
> admin
> generate

# Use for signing
gpg --sign document.txt

# Use for encryption
gpg --encrypt --recipient user@example.com file.txt

# Git commit signing
git config --global user.signingkey YOUR_KEY_ID
git config --global commit.gpgsign true
```

## Platform-Specific Notes

### macOS

**Installation**:

```bash
brew install ykman yubico-piv-tool libfido2
brew install --cask yubico-yubikey-manager yubico-authenticator
```

**Smart Card Support**:

- macOS has built-in smart card support
- YubiKey works immediately for PIV

**USB Permissions**:

- No special configuration needed

### Linux

**Installation**:

```bash
# Debian/Ubuntu
sudo apt install yubikey-manager yubico-piv-tool libfido2-1 fido2-tools

# Fedora
sudo dnf install yubikey-manager yubico-piv-tool libfido2 fido2-tools

# Arch
sudo pacman -S yubikey-manager yubico-piv-tool libfido2
```

**USB Permissions**:

```bash
# Add udev rules for YubiKey
wget https://raw.githubusercontent.com/Yubico/libfido2/main/udev/70-u2f.rules
sudo mv 70-u2f.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger

# Add user to plugdev group
sudo usermod -aG plugdev $USER
# Log out and back in
```

**Smart Card Support**:

```bash
# Install PCSC
sudo apt install pcscd  # Debian/Ubuntu
sudo dnf install pcsc-lite  # Fedora
sudo systemctl enable pcscd
sudo systemctl start pcscd
```

### Windows

**Installation**:

```powershell
# Using winget
winget install Yubico.YubikeyManager

# Or download from Yubico website
# https://www.yubico.com/support/download/
```

**Smart Card Support**:

- Windows has built-in smart card support
- Install YubiKey Minidriver for enhanced support

**OpenSSH**:

- Windows 10+ includes OpenSSH
- FIDO2 keys supported in OpenSSH 8.2+

## Troubleshooting

### YubiKey Not Detected

**macOS/Linux**:

```bash
# Check USB devices
lsusb | grep Yubico

# Check if ykman sees it
ykman list

# Check permissions (Linux)
ls -l /dev/hidraw*
groups  # Should include 'plugdev'
```

**Fix**:

```bash
# Linux: Add udev rules
sudo wget https://raw.githubusercontent.com/Yubico/yubikey-manager/main/resources/70-yubikey.rules \
  -O /etc/udev/rules.d/70-yubikey.rules
sudo udevadm control --reload-rules
```

### PIV Not Working

```bash
# Check PCSC daemon (Linux)
sudo systemctl status pcscd

# Check card status
yubico-piv-tool -a status

# Reset PIV (WARNING: Destroys all keys)
ykman piv reset
```

### FIDO2 SSH Not Working

```bash
# Check OpenSSH version (need 8.2+)
ssh -V

# Check for SK support
ssh-keygen -t ed25519-sk

# If error, install libfido2
brew install libfido2  # macOS
sudo apt install libfido2-1  # Linux
```

### Touch Not Registering

- **Try different USB port**
- **Check if touch is required**: `ykman fido info`
- **Update firmware**: Use YubiKey Manager
- **Clean sensor**: Gently wipe with soft cloth

## Security Best Practices

### 1. Always Have Backup Keys

Register multiple YubiKeys for critical services:

```bash
# SSH: Generate keys on 2 YubiKeys
ssh-keygen -t ed25519-sk -O resident  # Key 1
ssh-keygen -t ed25519-sk -O resident  # Key 2

# PAM U2F: Register 2 keys
pamu2fcfg > ~/.config/Yubico/u2f_keys       # Key 1
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys   # Key 2
```

### 2. Set PINs and PUKs

```bash
# FIDO2 PIN
ykman fido access change-pin

# PIV PIN (default: 123456)
ykman piv access change-pin

# PIV PUK (default: 12345678)
ykman piv access change-puk

# PIV Management Key
ykman piv access change-management-key
```

### 3. Store Recovery Codes

- Keep backup codes for 2FA
- Store PIV PUK securely
- Document key slots used

### 4. Physical Security

- Keep backup YubiKey in secure location
- Don't leave YubiKey plugged in when not needed
- Register removal notifications

## Resources

### Official Documentation

- **YubiKey**: <https://developers.yubico.com/>
- **FIDO Alliance**: <https://fidoalliance.org/>
- **Age Encryption**: <https://age-encryption.org/>

### YubiKey Manager

- **CLI Docs**: <https://docs.yubico.com/software/yubikey/tools/ykman/>
- **PIV Guide**: <https://developers.yubico.com/PIV/Guides/>
- **OATH Guide**: <https://developers.yubico.com/OATH/>

### Integration Guides

- **SSH**: <https://developers.yubico.com/SSH/>
- **GPG**: <https://github.com/drduh/YubiKey-Guide>
- **PAM**: <https://developers.yubico.com/pam-u2f/>

## Installation Quick Reference

### Essential YubiKey Setup

```bash
# macOS
brew install ykman yubico-piv-tool libfido2

# Linux (Debian/Ubuntu)
sudo apt install yubikey-manager yubico-piv-tool libfido2-1

# Linux (Fedora)
sudo dnf install yubikey-manager yubico-piv-tool libfido2

# Windows
winget install Yubico.YubikeyManager
```

### Full Security Keys Suite

```bash
# Using remote-script-runner
rsr pkg install secrets.security-keys

# Or individual tools
rsr pkg install yubikey-manager
rsr pkg install yubico-piv-tool
rsr pkg install libfido2
```

## Summary

**Total Tools**: 12 packages
**Categories**: YubiKey (5), FIDO2/U2F (4), Integration (3)
**Platform Support**: macOS ✅, Linux ✅, Windows ✅

**Essential Tools**:

1. yubikey-manager (ykman)
2. yubico-piv-tool
3. libfido2

**Recommended Tools**:
4. yubikey-manager-qt (GUI)
5. yubioath-desktop (2FA)
6. pam-u2f (system auth)
7. age-plugin-yubikey (encryption)

All tools validated and ready for use! 🔐

---

**Document Version**: 1.0
**Last Updated**: December 11, 2024
**Status**: ✅ Complete
