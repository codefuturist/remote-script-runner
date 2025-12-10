#!/usr/bin/env python3
"""
DNS Zone File to Pi-hole TOML Converter
Parses standard BIND zone files and converts them to Pi-hole v6 TOML format
Supports multiple zones, A/AAAA/CNAME records, and wildcards
Includes validation and error recovery mechanisms
"""

import re
import sys
import os
import logging
import ipaddress
import shutil
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set
from dataclasses import dataclass
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s][%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Validation constants
MAX_HOSTNAME_LENGTH = 253
MAX_LABEL_LENGTH = 63
MAX_CNAME_DEPTH = 10


@dataclass
class DNSRecord:
    """Represents a DNS record"""
    name: str
    ttl: int
    record_type: str
    value: str
    comment: Optional[str] = None
    zone_file: Optional[str] = None
    line_number: Optional[int] = None


class ValidationError(Exception):
    """Custom exception for validation errors"""
    pass


class DNSValidator:
    """Validates DNS records and zone files"""
    
    @staticmethod
    def validate_hostname(hostname: str) -> bool:
        """Validate hostname according to RFC 1035"""
        if not hostname or len(hostname) > MAX_HOSTNAME_LENGTH:
            return False
        
        # Allow wildcards
        if hostname.startswith('*.'):
            hostname = hostname[2:]
        
        # Split into labels
        labels = hostname.rstrip('.').split('.')
        
        for label in labels:
            if not label or len(label) > MAX_LABEL_LENGTH:
                return False
            
            # Label must start with alphanumeric
            if not label[0].isalnum():
                return False
            
            # Label must end with alphanumeric
            if not label[-1].isalnum():
                return False
            
            # Label can only contain alphanumeric and hyphens
            if not all(c.isalnum() or c == '-' for c in label):
                return False
        
        return True
    
    @staticmethod
    def validate_ip_address(ip: str, record_type: str) -> bool:
        """Validate IP address"""
        try:
            if record_type == 'A':
                ipaddress.IPv4Address(ip)
                return True
            elif record_type == 'AAAA':
                ipaddress.IPv6Address(ip)
                return True
        except ValueError:
            return False
        return False
    
    @staticmethod
    def validate_ttl(ttl: int) -> bool:
        """Validate TTL value"""
        return 0 <= ttl <= 2147483647  # RFC 1035 maximum
    
    @staticmethod
    def validate_record(record: DNSRecord) -> Tuple[bool, Optional[str]]:
        """Validate a single DNS record"""
        # Validate hostname
        if not DNSValidator.validate_hostname(record.name):
            return False, f"Invalid hostname: {record.name}"
        
        # Validate TTL
        if not DNSValidator.validate_ttl(record.ttl):
            return False, f"Invalid TTL: {record.ttl}"
        
        # Validate based on record type
        if record.record_type in ['A', 'AAAA']:
            if not DNSValidator.validate_ip_address(record.value, record.record_type):
                return False, f"Invalid IP address for {record.record_type}: {record.value}"
        
        elif record.record_type == 'CNAME':
            if not DNSValidator.validate_hostname(record.value):
                return False, f"Invalid CNAME target: {record.value}"
        
        return True, None


class ZoneFileParser:
    """Parse BIND zone files with validation"""
    
    def __init__(self, zone_file: Path):
        self.zone_file = zone_file
        self.origin = None
        self.records: List[DNSRecord] = []
        self.errors: List[str] = []
        self.warnings: List[str] = []
        
    def parse(self) -> List[DNSRecord]:
        """Parse zone file and return list of DNS records"""
        logger.info(f"Parsing zone file: {self.zone_file}")
        
        try:
            with open(self.zone_file, 'r') as f:
                lines = f.readlines()
        except Exception as e:
            error_msg = f"Failed to read zone file {self.zone_file}: {e}"
            logger.error(error_msg)
            self.errors.append(error_msg)
            raise ValidationError(error_msg)
        
        # Extract $ORIGIN
        for line in lines:
            if line.strip().startswith('$ORIGIN'):
                self.origin = line.split()[1].rstrip('.')
                logger.debug(f"Found $ORIGIN: {self.origin}")
                break
        
        if not self.origin:
            # Try to get origin from filename
            self.origin = self.zone_file.stem
            logger.warning(f"No $ORIGIN found, using filename: {self.origin}")
        
        # Parse records
        current_name = None
        for line_num, line in enumerate(lines, 1):
            line = line.strip()
            
            # Skip empty lines, comments, and directives
            if not line or line.startswith(';') or line.startswith('$'):
                continue
            
            # Extract inline comment
            comment = None
            if ';' in line:
                line, comment = line.split(';', 1)
                line = line.strip()
                comment = comment.strip()
            
            # Skip SOA and NS records (Pi-hole doesn't need these for local DNS)
            if ' SOA ' in line or ' NS ' in line:
                continue
            
            try:
                record = self._parse_record_line(line, current_name, comment, line_num)
                if record:
                    # Validate record
                    is_valid, error_msg = DNSValidator.validate_record(record)
                    if not is_valid:
                        warning = f"Line {line_num}: {error_msg} - skipping"
                        logger.warning(warning)
                        self.warnings.append(warning)
                        continue
                    
                    self.records.append(record)
                    current_name = record.name if record.name != '@' else None
            except Exception as e:
                warning = f"Failed to parse line {line_num}: {line} - {e}"
                logger.warning(warning)
                self.warnings.append(warning)
                continue
        
        logger.info(f"Parsed {len(self.records)} records from {self.zone_file}")
        if self.warnings:
            logger.warning(f"Zone file has {len(self.warnings)} warnings")
        
        return self.records
    
    def _parse_record_line(self, line: str, current_name: Optional[str], comment: Optional[str], line_num: int) -> Optional[DNSRecord]:
        """Parse a single DNS record line"""
        parts = line.split()
        if len(parts) < 4:
            return None
        
        # Try to parse: NAME TTL CLASS TYPE VALUE
        # or: NAME CLASS TYPE VALUE
        # or: TTL CLASS TYPE VALUE (continuation of previous name)
        
        name = None
        ttl = 3600  # default
        record_type = None
        value = None
        
        idx = 0
        
        # Check if first part is a name (not a number)
        if not parts[idx].isdigit():
            name = parts[idx]
            idx += 1
        else:
            name = current_name or '@'
        
        # Check for TTL
        if idx < len(parts) and parts[idx].isdigit():
            ttl = int(parts[idx])
            idx += 1
        
        # Skip CLASS (usually IN)
        if idx < len(parts) and parts[idx] in ['IN', 'CH', 'HS']:
            idx += 1
        
        # Get TYPE
        if idx < len(parts):
            record_type = parts[idx]
            idx += 1
        
        # Get VALUE (rest of line)
        if idx < len(parts):
            value = ' '.join(parts[idx:])
        
        if not record_type or not value:
            return None
        
        # Only process A, AAAA, and CNAME records
        if record_type not in ['A', 'AAAA', 'CNAME']:
            return None
        
        # Normalize name
        if name == '@':
            name = self.origin
        elif not name.endswith('.'):
            name = f"{name}.{self.origin}"
        else:
            name = name.rstrip('.')
        
        # Normalize value for CNAME
        if record_type == 'CNAME':
            if value == '@':
                value = self.origin
            elif not value.endswith('.'):
                value = f"{value}.{self.origin}"
            else:
                value = value.rstrip('.')
        
        return DNSRecord(
            name=name, 
            ttl=ttl, 
            record_type=record_type, 
            value=value, 
            comment=comment,
            zone_file=str(self.zone_file),
            line_number=line_num
        )


class PiholeHostsConverter:
    """Convert DNS records to Pi-hole TOML hosts format with validation"""
    
    def __init__(self, records: List[DNSRecord]):
        self.records = records
        self.hosts_map: Dict[str, str] = {}
        self.cname_map: Dict[str, str] = {}
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.duplicate_hosts: Dict[str, List[str]] = {}  # hostname -> [IPs]
    
    def convert(self) -> List[str]:
        """Convert DNS records to Pi-hole hosts format with validation"""
        logger.info("Converting DNS records to Pi-hole hosts format")
        
        # First pass: collect all A/AAAA records and detect duplicates
        for record in self.records:
            if record.record_type in ['A', 'AAAA']:
                if record.name in self.hosts_map:
                    # Duplicate hostname
                    if record.name not in self.duplicate_hosts:
                        self.duplicate_hosts[record.name] = [self.hosts_map[record.name]]
                    self.duplicate_hosts[record.name].append(record.value)
                    
                    warning = f"Duplicate hostname '{record.name}' at {record.zone_file}:{record.line_number}"
                    logger.warning(warning)
                    self.warnings.append(warning)
                    
                    # Use the last occurrence (could make this configurable)
                    logger.info(f"Using latest IP for {record.name}: {record.value}")
                
                self.hosts_map[record.name] = record.value
        
        # Second pass: resolve CNAME records and detect duplicates
        for record in self.records:
            if record.record_type == 'CNAME':
                if record.name in self.cname_map:
                    warning = f"Duplicate CNAME '{record.name}' at {record.zone_file}:{record.line_number}"
                    logger.warning(warning)
                    self.warnings.append(warning)
                
                self.cname_map[record.name] = record.value
        
        # Resolve CNAMEs to their ultimate IP
        resolved_cnames = {}
        for cname, target in self.cname_map.items():
            ip = self._resolve_cname(target)
            if ip:
                resolved_cnames[cname] = ip
            else:
                error = f"Failed to resolve CNAME '{cname}' -> '{target}'"
                logger.error(error)
                self.errors.append(error)
        
        # Merge everything
        all_hosts = {**self.hosts_map, **resolved_cnames}
        
        # Convert to Pi-hole hosts format: "IP HOSTNAME"
        hosts_lines = []
        for hostname, ip in sorted(all_hosts.items()):
            hosts_lines.append(f"{ip} {hostname}")
        
        logger.info(f"Converted {len(hosts_lines)} DNS records to hosts format")
        
        if self.duplicate_hosts:
            logger.warning(f"Found {len(self.duplicate_hosts)} duplicate hostnames")
        
        if self.errors:
            logger.error(f"Conversion completed with {len(self.errors)} errors")
        
        return hosts_lines
    
    def _resolve_cname(self, target: str, depth: int = 0, seen: set = None) -> Optional[str]:
        """Resolve CNAME chain to final IP address"""
        if depth > 10:  # Prevent infinite loops
            logger.warning(f"CNAME chain too deep for {target}")
            return None
        
        if seen is None:
            seen = set()
        
        if target in seen:
            logger.warning(f"Circular CNAME detected for {target}")
            return None
        
        seen.add(target)
        
        # Check if target is an A/AAAA record
        if target in self.hosts_map:
            return self.hosts_map[target]
        
        # Check if target is another CNAME
        if target in self.cname_map:
            return self._resolve_cname(self.cname_map[target], depth + 1, seen)
        
        logger.warning(f"Could not resolve CNAME target: {target}")
        return None


class PiholeTomlUpdater:
    """Update Pi-hole pihole.toml with new DNS records (with backup and validation)"""
    
    def __init__(self, toml_file: Path):
        self.toml_file = toml_file
        self.backup_file: Optional[Path] = None
    
    def create_backup(self) -> bool:
        """Create backup of current pihole.toml"""
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        self.backup_file = Path(f"{self.toml_file}.backup-{timestamp}")
        
        try:
            shutil.copy2(self.toml_file, self.backup_file)
            logger.info(f"Created backup: {self.backup_file}")
            return True
        except Exception as e:
            logger.error(f"Failed to create backup: {e}")
            return False
    
    def restore_backup(self) -> bool:
        """Restore from backup"""
        if not self.backup_file or not self.backup_file.exists():
            logger.error("No backup file available for restore")
            return False
        
        try:
            shutil.copy2(self.backup_file, self.toml_file)
            logger.info(f"Restored from backup: {self.backup_file}")
            return True
        except Exception as e:
            logger.error(f"Failed to restore backup: {e}")
            return False
    
    def validate_toml_syntax(self, content: str) -> bool:
        """Basic TOML syntax validation"""
        # Check for basic TOML structure
        if 'hosts = [' not in content:
            logger.error("Missing hosts array in TOML")
            return False
        
        # Check for balanced brackets
        if content.count('[') != content.count(']'):
            logger.error("Unbalanced brackets in TOML")
            return False
        
        return True
    
    def update(self, hosts_lines: List[str], dry_run: bool = False) -> bool:
        """Update pihole.toml with new hosts array"""
        logger.info(f"Updating {self.toml_file} with {len(hosts_lines)} hosts (dry_run={dry_run})")
        
        # Validate input
        if not hosts_lines:
            logger.error("No hosts to update")
            return False
        
        # Create backup before making changes
        if not dry_run and not self.create_backup():
            logger.error("Failed to create backup, aborting update")
            return False
        
        try:
            with open(self.toml_file, 'r') as f:
                original_content = f.read()
        except Exception as e:
            logger.error(f"Failed to read {self.toml_file}: {e}")
            return False
        
        # Build new hosts array
        hosts_entries = ',\n    '.join(f'"{line}"' for line in hosts_lines)
        new_hosts_block = f'hosts = [\n    {hosts_entries}\n  ]'
        
        # Replace hosts array using regex
        # Match: hosts = [ ... ] with optional ### CHANGED comment
        pattern = r'hosts\s*=\s*\[[^\]]*\](?:\s*###[^\n]*)?'
        
        if not re.search(pattern, original_content, re.DOTALL):
            logger.error("Could not find hosts array in pihole.toml")
            return False
        
        new_content = re.sub(
            pattern, 
            new_hosts_block + ' ### CHANGED, default = []', 
            original_content, 
            flags=re.DOTALL
        )
        
        # Validate new content
        if not self.validate_toml_syntax(new_content):
            logger.error("Generated TOML has invalid syntax")
            return False
        
        # Verify the change was made
        if new_content == original_content:
            logger.warning("No changes detected in TOML content")
        
        # Dry run mode - don't actually write
        if dry_run:
            logger.info("Dry run mode - would update pihole.toml")
            return True
        
        # Write back
        try:
            with open(self.toml_file, 'w') as f:
                f.write(new_content)
            logger.info("Successfully updated pihole.toml")
            
            # Verify the file is readable after write
            with open(self.toml_file, 'r') as f:
                verify_content = f.read()
            
            if verify_content != new_content:
                logger.error("Verification failed - content mismatch after write")
                self.restore_backup()
                return False
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to write {self.toml_file}: {e}")
            # Attempt to restore backup
            if self.restore_backup():
                logger.info("Successfully restored from backup after write failure")
            return False


def main():
    """Main entry point with comprehensive validation and error handling"""
    # Parse command line arguments
    dry_run = '--dry-run' in sys.argv
    if dry_run:
        sys.argv.remove('--dry-run')
        logger.info("Running in DRY RUN mode - no changes will be applied")
    
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} [--dry-run] <zones_directory> <pihole_toml_file>")
        sys.exit(1)
    
    zones_dir = Path(sys.argv[1])
    pihole_toml = Path(sys.argv[2])
    cache_dir = Path("/var/cache/gitops-dns")
    
    # Ensure cache directory exists
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        logger.warning(f"Failed to create cache directory: {e}")
    
    # Validation phase
    logger.info("=" * 60)
    logger.info("DNS ZONE SYNC - VALIDATION PHASE")
    logger.info("=" * 60)
    
    # Validate inputs
    if not zones_dir.is_dir():
        logger.error(f"Zones directory not found: {zones_dir}")
        sys.exit(1)
    
    if not pihole_toml.exists():
        logger.error(f"Pi-hole TOML file not found: {pihole_toml}")
        sys.exit(1)
    
    # Check write permissions
    if not dry_run and not os.access(pihole_toml, os.W_OK):
        logger.error(f"No write permission for {pihole_toml}")
        sys.exit(1)
    
    # Find all zone files
    zone_files = sorted(zones_dir.glob("*.zone"))
    if not zone_files:
        logger.warning(f"No .zone files found in {zones_dir}")
        sys.exit(0)
    
    logger.info(f"Found {len(zone_files)} zone files")
    for zf in zone_files:
        logger.info(f"  - {zf.name}")
    
    # Parse all zone files with error tracking - VALIDATE FIRST, APPLY ONLY IF ALL VALID
    all_records = []
    parse_errors = []
    parse_warnings = []
    valid_zones = []
    invalid_zones = []
    
    logger.info("=" * 60)
    logger.info("PHASE 1: PRE-VALIDATION - NO CHANGES WILL BE MADE")
    logger.info("=" * 60)
    
    # First pass: Validate ALL zone files before making ANY changes
    for zone_file in zone_files:
        zone_name = zone_file.name
        logger.info(f"Pre-validating: {zone_name}")
        
        try:
            parser = ZoneFileParser(zone_file)
            records = parser.parse()
            
            # Check for errors in this zone
            if parser.errors:
                error_msg = f"Zone {zone_name} has {len(parser.errors)} errors"
                logger.error(error_msg)
                parse_errors.extend(parser.errors)
                invalid_zones.append(zone_name)
                continue
            
            # Zone is valid
            valid_zones.append(zone_name)
            all_records.extend(records)
            
            if parser.warnings:
                parse_warnings.extend(parser.warnings)
                
        except ValidationError as e:
            error_msg = f"Validation error in {zone_name}: {e}"
            logger.error(error_msg)
            parse_errors.append(error_msg)
            invalid_zones.append(zone_name)
        except Exception as e:
            error_msg = f"Failed to parse {zone_name}: {e}"
            logger.error(error_msg)
            parse_errors.append(error_msg)
            invalid_zones.append(zone_name)
    
    # Report validation results
    logger.info("=" * 60)
    logger.info("PRE-VALIDATION RESULTS")
    logger.info("=" * 60)
    logger.info(f"Valid zones: {len(valid_zones)}/{len(zone_files)}")
    for zone in valid_zones:
        logger.info(f"  ✓ {zone}")
    
    if invalid_zones:
        logger.error(f"Invalid zones: {len(invalid_zones)}/{len(zone_files)}")
        for zone in invalid_zones:
            logger.error(f"  ✗ {zone}")
    
    # CRITICAL: Only proceed if ALL zones are valid
    if parse_errors or invalid_zones:
        logger.error("=" * 60)
        logger.error("VALIDATION FAILED - ABORTING")
        logger.error("=" * 60)
        logger.error(f"Found {len(parse_errors)} critical errors")
        for error in parse_errors[:10]:
            logger.error(f"  - {error}")
        if len(parse_errors) > 10:
            logger.error(f"  ... and {len(parse_errors) - 10} more errors")
        
        # Cache validation failure
        cache_file = cache_dir / "last_validation_failed"
        try:
            with open(cache_file, 'w') as f:
                f.write(f"{datetime.now().isoformat()}\n")
                f.write(f"Invalid zones: {', '.join(invalid_zones)}\n")
                f.write(f"Error count: {len(parse_errors)}\n")
        except:
            pass
        
        logger.error("NO CHANGES APPLIED - Destination config untouched")
        logger.error("Fix zone file errors and retry")
        sys.exit(1)
    
    # All zones valid - safe to proceed
    logger.info("=" * 60)
    logger.info("✓ ALL ZONE FILES VALID - PROCEEDING")
    logger.info("=" * 60)
    
    if parse_warnings:
        logger.warning(f"Found {len(parse_warnings)} warnings during parsing")
    
    if not all_records:
        logger.warning("No DNS records found after parsing")
        sys.exit(0)
    
    logger.info(f"Successfully parsed {len(all_records)} DNS records")
    
    # Convert to Pi-hole format with validation
    logger.info("=" * 60)
    logger.info("PHASE 2: CONVERSION & FINAL VALIDATION")
    logger.info("=" * 60)
    
    converter = PiholeHostsConverter(all_records)
    hosts_lines = converter.convert()
    
    # Check for conversion errors
    if converter.errors:
        logger.error("=" * 60)
        logger.error("CONVERSION VALIDATION FAILED - ABORTING")
        logger.error("=" * 60)
        logger.error(f"Found {len(converter.errors)} critical errors during conversion:")
        for error in converter.errors[:10]:
            logger.error(f"  - {error}")
        if len(converter.errors) > 10:
            logger.error(f"  ... and {len(converter.errors) - 10} more errors")
        
        # Cache conversion failure
        cache_file = cache_dir / "last_conversion_failed"
        try:
            with open(cache_file, 'w') as f:
                f.write(f"{datetime.now().isoformat()}\n")
                f.write(f"Conversion errors: {len(converter.errors)}\n")
                for error in converter.errors[:5]:
                    f.write(f"  {error}\n")
        except:
            pass
        
        logger.error("NO CHANGES APPLIED - Destination config untouched")
        logger.error("Fix CNAME resolution errors and retry")
        sys.exit(1)
    
    if converter.warnings:
        logger.warning(f"Found {len(converter.warnings)} warnings during conversion")
        for warning in converter.warnings[:3]:
            logger.warning(f"  - {warning}")
    
    if not hosts_lines:
        logger.error("No hosts generated after conversion")
        sys.exit(1)
    
    logger.info(f"Successfully converted to {len(hosts_lines)} Pi-hole hosts entries")
    
    # Cache validated configuration before applying
    cache_file = cache_dir / "validated_hosts.cache"
    try:
        with open(cache_file, 'w') as f:
            f.write(f"# Generated: {datetime.now().isoformat()}\n")
            f.write(f"# Valid zones: {', '.join(valid_zones)}\n")
            f.write(f"# Total records: {len(all_records)}\n")
            f.write(f"# Hosts entries: {len(hosts_lines)}\n")
            f.write("# --- VALIDATED CONFIGURATION ---\n")
            for line in hosts_lines:
                f.write(line + "\n")
        logger.debug(f"Cached validated configuration: {cache_file}")
    except Exception as e:
        logger.warning(f"Failed to cache validated config: {e}")
    
    # Summary before applying
    logger.info("=" * 60)
    logger.info("VALIDATION SUMMARY - ALL CHECKS PASSED")
    logger.info("=" * 60)
    logger.info(f"Zone files processed: {len(zone_files)}")
    logger.info(f"DNS records parsed: {len(all_records)}")
    logger.info(f"Hosts entries generated: {len(hosts_lines)}")
    logger.info(f"Parse warnings: {len(parse_warnings)}")
    logger.info(f"Conversion warnings: {len(converter.warnings)}")
    logger.info(f"Duplicate hostnames: {len(converter.duplicate_hosts)}")
    
    if converter.duplicate_hosts:
        logger.warning("Duplicate hostnames detected:")
        for hostname, ips in list(converter.duplicate_hosts.items())[:3]:
            logger.warning(f"  - {hostname}: {ips}")
    
    # Apply changes phase - ONLY after all validations pass
    logger.info("=" * 60)
    logger.info("PHASE 3: APPLICATION - Applying validated configuration")
    logger.info("=" * 60)
    logger.info("⚠️  All validations passed - NOW modifying destination config")
    
    updater = PiholeTomlUpdater(pihole_toml)
    
    if updater.update(hosts_lines, dry_run=dry_run):
        if dry_run:
            logger.info("=" * 60)
            logger.info("✓ DRY RUN SUCCESSFUL")
            logger.info("=" * 60)
            logger.info("All validations passed - no changes applied")
            logger.info("Safe to apply in production")
        else:
            logger.info("=" * 60)
            logger.info("✓ DNS SYNC SUCCESSFUL")
            logger.info("=" * 60)
            logger.info("Validated configuration applied successfully")
            
            # Update success cache
            cache_file = cache_dir / "last_successful_sync"
            try:
                with open(cache_file, 'w') as f:
                    f.write(f"{datetime.now().isoformat()}\n")
                    f.write(f"Zones: {', '.join(valid_zones)}\n")
                    f.write(f"Records: {len(all_records)}\n")
                    f.write(f"Hosts: {len(hosts_lines)}\n")
            except:
                pass
        
        logger.info("=" * 60)
        sys.exit(0)
    else:
        logger.error("=" * 60)
        logger.error("✗ APPLICATION FAILED")
        logger.error("=" * 60)
        logger.error("Validated config could not be applied")
        logger.error("Check logs and backup restored if needed")
        logger.error("=" * 60)
        sys.exit(1)


if __name__ == "__main__":
    main()
