"""Chocolatey package validator."""

import requests
import xml.etree.ElementTree as ET
from .base import PackageValidator, ValidationResult


class ChocoValidator(PackageValidator):
    """Validates Chocolatey packages."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'choco'

    def validate(self, package: str) -> ValidationResult:
        """Validate Chocolatey package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            # OData API query
            url = f"https://community.chocolatey.org/api/v2/Packages?$filter=Id eq '{package}'"
            response = requests.get(url, timeout=15)

            if response.status_code == 200:
                # Parse XML response
                root = ET.fromstring(response.content)
                # Check if any entries exist
                ns = {'atom': 'http://www.w3.org/2005/Atom'}
                entries = root.findall('.//atom:entry', ns)

                if entries:
                    result = ValidationResult(package, 'choco', 'verified',
                                             details='Found in Chocolatey repository')
                else:
                    result = ValidationResult(package, 'choco', 'not_found',
                                             details='Not found in Chocolatey repository')
            else:
                result = ValidationResult(package, 'choco', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'choco', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
