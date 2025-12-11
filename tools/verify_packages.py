#!/usr/bin/env -S uv run
"""
Package Verification Tool for remote-script-runner.

Verifies package names across all YAML profiles and package managers.
"""

import argparse
import json
import os
import sys
import yaml
from pathlib import Path
from typing import Dict, List, Tuple, Set
from collections import defaultdict

# Add package_validators to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from package_validators import (
    BrewValidator, NpmValidator, PyPiValidator, CargoValidator,
    ChocoValidator, WingetValidator, ScoopValidator, KrewValidator,
    PacmanValidator, SnapValidator, MacPortsValidator, FallbackValidator
)
from package_validators.brew_validator import BrewCaskValidator


class PackageVerifier:
    """Main package verification orchestrator."""

    def __init__(self, cache_file: str = None):
        self.cache_file = cache_file or os.path.join(
            os.path.dirname(__file__), 'cache', 'package_cache.json'
        )
        self.cache = self._load_cache()
        self.validators = self._init_validators()
        self.results = {
            'verified': [],
            'not_found': [],
            'unverifiable': [],
            'errors': []
        }

    def _load_cache(self) -> Dict:
        """Load cache from file."""
        if os.path.exists(self.cache_file):
            try:
                with open(self.cache_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Warning: Failed to load cache: {e}")
        return {}

    def _save_cache(self):
        """Save cache to file."""
        os.makedirs(os.path.dirname(self.cache_file), exist_ok=True)
        with open(self.cache_file, 'w') as f:
            json.dump(self.cache, f, indent=2)

    def _init_validators(self) -> Dict:
        """Initialize validators for each package manager."""
        return {
            'brew': BrewValidator(self.cache),
            'brew_cask': BrewCaskValidator(self.cache),
            'npm': NpmValidator(self.cache),
            'pip': PyPiValidator(self.cache),
            'cargo': CargoValidator(self.cache),
            'choco': ChocoValidator(self.cache),
            'winget': WingetValidator(self.cache),
            'scoop': ScoopValidator(self.cache),
            'krew': KrewValidator(self.cache),
            'pacman': PacmanValidator(self.cache),
            'snap': SnapValidator(self.cache),
            'macports': MacPortsValidator(self.cache),
            'pipx': FallbackValidator('pipx', self.cache),
            'apt': FallbackValidator('apt', self.cache),
            'dnf': FallbackValidator('dnf', self.cache),
            'yum': FallbackValidator('yum', self.cache),
            'zypper': FallbackValidator('zypper', self.cache),
        }

    def parse_yaml_profile(self, filepath: str) -> List[Tuple[str, str, str]]:
        """
        Parse YAML profile and extract package-manager pairs.

        Returns:
            List of (package_name, manager, profile_file) tuples
        """
        packages = []
        profile_name = os.path.basename(filepath)

        try:
            with open(filepath, 'r') as f:
                data = yaml.safe_load(f)

            if not data:
                return packages

            # Parse top-level packages
            if 'packages' in data and isinstance(data['packages'], list):
                for pkg in data['packages']:
                    if isinstance(pkg, str):
                        # Simple string package (usually for scripts)
                        continue
                    elif isinstance(pkg, dict):
                        self._extract_package_managers(pkg, packages, profile_name)

            # Parse groups
            if 'groups' in data:
                for group_name, group_data in data['groups'].items():
                    if isinstance(group_data, dict) and 'packages' in group_data:
                        for pkg in group_data['packages']:
                            if isinstance(pkg, dict):
                                self._extract_package_managers(pkg, packages, profile_name)

        except Exception as e:
            print(f"Error parsing {filepath}: {e}")

        return packages

    def _extract_package_managers(self, pkg_dict: Dict, packages: List, profile: str):
        """Extract package-manager pairs from package dictionary."""
        pkg_name = pkg_dict.get('name', 'unknown')

        # Known package managers
        managers = [
            'brew', 'brew_cask', 'apt', 'dnf', 'yum', 'zypper', 'pacman',
            'winget', 'choco', 'scoop', 'npm', 'pip', 'pipx', 'cargo',
            'snap', 'macports', 'krew'
        ]

        for manager in managers:
            if manager in pkg_dict:
                pkg_value = pkg_dict[manager]
                if isinstance(pkg_value, str):
                    packages.append((pkg_value, manager, profile))
                elif isinstance(pkg_value, list):
                    for p in pkg_value:
                        if isinstance(p, str):
                            packages.append((p, manager, profile))

    def verify_packages(self, packages: List[Tuple[str, str, str]],
                       manager_filter: str = None) -> Dict:
        """
        Verify list of packages.

        Args:
            packages: List of (package, manager, profile) tuples
            manager_filter: Optional manager to filter by

        Returns:
            Summary statistics
        """
        total = len(packages)
        processed = 0

        for package, manager, profile in packages:
            if manager_filter and manager != manager_filter:
                continue

            processed += 1
            if processed % 50 == 0:
                print(f"Progress: {processed}/{total} packages verified...")

            validator = self.validators.get(manager)
            if not validator:
                self.results['errors'].append({
                    'file': profile,
                    'package': package,
                    'manager': manager,
                    'status': 'error',
                    'details': f'No validator for {manager}'
                })
                continue

            result = validator.validate(package)

            entry = {
                'file': profile,
                'package': package,
                'manager': manager,
                'details': result.details,
            }

            if result.suggestion:
                entry['suggestion'] = result.suggestion

            if result.status == 'verified':
                self.results['verified'].append(entry)
            elif result.status == 'not_found':
                self.results['not_found'].append(entry)
            elif result.status == 'unverifiable':
                self.results['unverifiable'].append(entry)
            else:
                self.results['errors'].append(entry)

        return self._generate_summary()

    def _generate_summary(self) -> Dict:
        """Generate summary statistics."""
        total = (len(self.results['verified']) +
                len(self.results['not_found']) +
                len(self.results['unverifiable']) +
                len(self.results['errors']))

        return {
            'total': total,
            'verified': len(self.results['verified']),
            'not_found': len(self.results['not_found']),
            'unverifiable': len(self.results['unverifiable']),
            'errors': len(self.results['errors'])
        }

    def generate_report(self, format: str = 'text') -> str:
        """Generate report in specified format."""
        if format == 'json':
            return self._generate_json_report()
        elif format == 'markdown':
            return self._generate_markdown_report()
        else:
            return self._generate_text_report()

    def _generate_json_report(self) -> str:
        """Generate JSON report."""
        output = {
            'summary': self._generate_summary(),
            'verified': self.results['verified'],
            'not_found': self.results['not_found'],
            'unverifiable': self.results['unverifiable'],
            'errors': self.results['errors']
        }
        return json.dumps(output, indent=2)

    def _generate_text_report(self) -> str:
        """Generate text report."""
        lines = []
        summary = self._generate_summary()

        lines.append("=" * 70)
        lines.append("Package Verification Report")
        lines.append("=" * 70)
        lines.append(f"Total packages:    {summary['total']}")
        lines.append(f"Verified:          {summary['verified']} ✓")
        lines.append(f"Not found:         {summary['not_found']} ✗")
        lines.append(f"Unverifiable:      {summary['unverifiable']} ?")
        lines.append(f"Errors:            {summary['errors']} ⚠")
        lines.append("")

        if self.results['not_found']:
            lines.append("-" * 70)
            lines.append("NOT FOUND PACKAGES:")
            lines.append("-" * 70)
            for item in self.results['not_found']:
                lines.append(f"  [{item['manager']}] {item['package']}")
                lines.append(f"    File: {item['file']}")
                lines.append(f"    Details: {item['details']}")
                if 'suggestion' in item:
                    lines.append(f"    Suggestion: {item['suggestion']}")
                lines.append("")

        if self.results['errors']:
            lines.append("-" * 70)
            lines.append("ERRORS:")
            lines.append("-" * 70)
            for item in self.results['errors']:
                lines.append(f"  [{item['manager']}] {item['package']}")
                lines.append(f"    File: {item['file']}")
                lines.append(f"    Details: {item['details']}")
                lines.append("")

        return "\n".join(lines)

    def _generate_markdown_report(self) -> str:
        """Generate Markdown report."""
        lines = []
        summary = self._generate_summary()

        lines.append("# Package Verification Report")
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("| Metric | Count |")
        lines.append("|--------|-------|")
        lines.append(f"| Total packages | {summary['total']} |")
        lines.append(f"| ✓ Verified | {summary['verified']} |")
        lines.append(f"| ✗ Not found | {summary['not_found']} |")
        lines.append(f"| ? Unverifiable | {summary['unverifiable']} |")
        lines.append(f"| ⚠ Errors | {summary['errors']} |")
        lines.append("")

        if self.results['not_found']:
            lines.append("## Not Found Packages")
            lines.append("")
            lines.append("| Package | Manager | Profile | Details |")
            lines.append("|---------|---------|---------|---------|")
            for item in self.results['not_found']:
                suggestion = f" (Suggestion: {item['suggestion']})" if 'suggestion' in item else ""
                lines.append(f"| `{item['package']}` | {item['manager']} | {item['file']} | {item['details']}{suggestion} |")
            lines.append("")

        if self.results['errors']:
            lines.append("## Errors")
            lines.append("")
            lines.append("| Package | Manager | Profile | Details |")
            lines.append("|---------|---------|---------|---------|")
            for item in self.results['errors']:
                lines.append(f"| `{item['package']}` | {item['manager']} | {item['file']} | {item['details']} |")
            lines.append("")

        return "\n".join(lines)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Verify package names across all YAML profiles'
    )
    parser.add_argument(
        '--profile',
        help='Verify specific profile only'
    )
    parser.add_argument(
        '--manager',
        help='Verify specific package manager only'
    )
    parser.add_argument(
        '--format',
        choices=['text', 'json', 'markdown'],
        default='text',
        help='Output format (default: text)'
    )
    parser.add_argument(
        '--ci',
        action='store_true',
        help='CI mode: exit 1 if errors found'
    )
    parser.add_argument(
        '--refresh-cache',
        action='store_true',
        help='Refresh cache (ignore existing cache)'
    )
    parser.add_argument(
        '--config-dir',
        default='config/packages',
        help='Directory containing package YAML files'
    )

    args = parser.parse_args()

    # Initialize verifier
    verifier = PackageVerifier()
    if args.refresh_cache:
        verifier.cache = {}

    # Find YAML files
    config_dir = Path(args.config_dir)
    if args.profile:
        yaml_files = [config_dir / args.profile]
    else:
        yaml_files = list(config_dir.glob('*.yaml')) + list(config_dir.glob('*.yml'))

    # Parse all packages
    all_packages = []
    for yaml_file in yaml_files:
        if yaml_file.exists():
            packages = verifier.parse_yaml_profile(str(yaml_file))
            all_packages.extend(packages)

    print(f"Found {len(all_packages)} package-manager pairs in {len(yaml_files)} profiles")
    print("Starting verification...")
    print("")

    # Verify packages
    summary = verifier.verify_packages(all_packages, args.manager)

    # Save cache
    verifier._save_cache()

    # Generate report
    report = verifier.generate_report(args.format)
    print(report)

    # CI mode
    if args.ci:
        if summary['not_found'] > 0 or summary['errors'] > 0:
            sys.exit(1)


if __name__ == '__main__':
    main()
