#!/usr/bin/env bats
# test/lib/test_validate.bats - Tests for RSR Validation Library
#
# Run with: bats test/lib/test_validate.bats

setup() {
    export RSR_NO_COLOR=1
    source "${BATS_TEST_DIRNAME}/../../lib/core/init.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/core/validate.sh"
}

# =============================================================================
# Username Validation Tests
# =============================================================================

@test "rsr_validate_username accepts valid username" {
    run rsr_validate_username "john"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_username accepts username with numbers" {
    run rsr_validate_username "john123"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_username accepts username with underscore" {
    run rsr_validate_username "john_doe"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_username accepts username with hyphen" {
    run rsr_validate_username "john-doe"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_username rejects empty username" {
    run rsr_validate_username ""
    [ "$status" -eq 1 ]
}

@test "rsr_validate_username rejects username starting with number" {
    run rsr_validate_username "1john"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_username rejects username with uppercase" {
    run rsr_validate_username "John"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_username rejects username with special chars" {
    run rsr_validate_username "john@doe"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_username rejects username > 32 chars" {
    run rsr_validate_username "abcdefghijklmnopqrstuvwxyz1234567"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Password Validation Tests
# =============================================================================

@test "rsr_validate_password accepts valid password" {
    run rsr_validate_password "password123"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_password rejects short password" {
    run rsr_validate_password "short"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_password accepts custom min length" {
    run rsr_validate_password "abcd" 4
    [ "$status" -eq 0 ]
}

@test "rsr_validate_password_complex accepts complex password" {
    run rsr_validate_password_complex "MyP@ssw0rd"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_password_complex rejects no uppercase" {
    run rsr_validate_password_complex "myp@ssw0rd"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_password_complex rejects no lowercase" {
    run rsr_validate_password_complex "MYP@SSW0RD"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_password_complex rejects no number" {
    run rsr_validate_password_complex "MyP@ssword"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_password_complex rejects no special char" {
    run rsr_validate_password_complex "MyPassw0rd"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Path Validation Tests
# =============================================================================

@test "rsr_validate_path_exists returns 0 for existing path" {
    run rsr_validate_path_exists "/tmp"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_path_exists returns 1 for non-existing path" {
    run rsr_validate_path_exists "/nonexistent/path/12345"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_file returns 0 for existing file" {
    run rsr_validate_file "/etc/passwd"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_directory returns 0 for existing directory" {
    run rsr_validate_directory "/tmp"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_path_safe accepts normal path" {
    run rsr_validate_path_safe "/home/user/file.txt"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_path_safe rejects empty path" {
    run rsr_validate_path_safe ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# Network Validation Tests
# =============================================================================

@test "rsr_validate_ipv4 accepts valid IPv4" {
    run rsr_validate_ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_ipv4 accepts 0.0.0.0" {
    run rsr_validate_ipv4 "0.0.0.0"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_ipv4 accepts 255.255.255.255" {
    run rsr_validate_ipv4 "255.255.255.255"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_ipv4 rejects invalid octet" {
    run rsr_validate_ipv4 "192.168.1.256"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_ipv4 rejects incomplete address" {
    run rsr_validate_ipv4 "192.168.1"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_ipv6 accepts valid IPv6" {
    run rsr_validate_ipv6 "2001:db8::1"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_hostname accepts valid hostname" {
    run rsr_validate_hostname "server.example.com"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_hostname accepts simple hostname" {
    run rsr_validate_hostname "localhost"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_hostname rejects hostname starting with hyphen" {
    run rsr_validate_hostname "-invalid.com"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_port accepts valid port" {
    run rsr_validate_port 8080
    [ "$status" -eq 0 ]
}

@test "rsr_validate_port accepts port 1" {
    run rsr_validate_port 1
    [ "$status" -eq 0 ]
}

@test "rsr_validate_port accepts port 65535" {
    run rsr_validate_port 65535
    [ "$status" -eq 0 ]
}

@test "rsr_validate_port rejects port 0" {
    run rsr_validate_port 0
    [ "$status" -eq 1 ]
}

@test "rsr_validate_port rejects port > 65535" {
    run rsr_validate_port 65536
    [ "$status" -eq 1 ]
}

@test "rsr_validate_url accepts valid HTTP URL" {
    run rsr_validate_url "http://example.com"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_url accepts valid HTTPS URL" {
    run rsr_validate_url "https://example.com/path"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_url rejects invalid URL" {
    run rsr_validate_url "not-a-url"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Numeric Validation Tests
# =============================================================================

@test "rsr_validate_integer accepts positive integer" {
    run rsr_validate_integer "123"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_integer accepts negative integer" {
    run rsr_validate_integer "-123"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_integer accepts zero" {
    run rsr_validate_integer "0"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_integer rejects decimal" {
    run rsr_validate_integer "1.5"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_integer rejects text" {
    run rsr_validate_integer "abc"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_positive_integer accepts positive" {
    run rsr_validate_positive_integer "5"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_positive_integer rejects zero" {
    run rsr_validate_positive_integer "0"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_integer_range accepts in-range value" {
    run rsr_validate_integer_range "50" 1 100
    [ "$status" -eq 0 ]
}

@test "rsr_validate_integer_range rejects below range" {
    run rsr_validate_integer_range "0" 1 100
    [ "$status" -eq 1 ]
}

@test "rsr_validate_integer_range rejects above range" {
    run rsr_validate_integer_range "101" 1 100
    [ "$status" -eq 1 ]
}

# =============================================================================
# Email Validation Tests
# =============================================================================

@test "rsr_validate_email accepts valid email" {
    run rsr_validate_email "user@example.com"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_email accepts email with subdomain" {
    run rsr_validate_email "user@mail.example.com"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_email rejects invalid email" {
    run rsr_validate_email "not-an-email"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_email rejects email without domain" {
    run rsr_validate_email "user@"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Generic Validation Tests
# =============================================================================

@test "rsr_validate_pattern accepts matching pattern" {
    run rsr_validate_pattern "test123" '^[a-z]+[0-9]+$'
    [ "$status" -eq 0 ]
}

@test "rsr_validate_pattern rejects non-matching pattern" {
    run rsr_validate_pattern "123test" '^[a-z]+[0-9]+$'
    [ "$status" -eq 1 ]
}

@test "rsr_validate_in_list accepts value in list" {
    run rsr_validate_in_list "apple" "apple" "banana" "cherry"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_in_list rejects value not in list" {
    run rsr_validate_in_list "orange" "apple" "banana" "cherry"
    [ "$status" -eq 1 ]
}

@test "rsr_validate_not_empty accepts non-empty string" {
    run rsr_validate_not_empty "hello"
    [ "$status" -eq 0 ]
}

@test "rsr_validate_not_empty rejects empty string" {
    run rsr_validate_not_empty ""
    [ "$status" -eq 1 ]
}

