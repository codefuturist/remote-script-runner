"""MacPorts package validator."""

import requests
from .base import PackageValidator, ValidationResult


class MacPortsValidator(PackageValidator):
    """Validates MacPorts packages."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'macports'

    def validate(self, package: str) -> ValidationResult:
        """Validate MacPorts package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            url = f"https://ports.macports.org/api/v1/ports/{package}/"
            response = requests.get(url, timeout=15)

            if response.status_code == 200:
                result = ValidationResult(package, 'macports', 'verified',
                                         details='Found in MacPorts')
            elif response.status_code == 404:
                result = ValidationResult(package, 'macports', 'not_found',
                                         details='Not found in MacPorts')
            else:
                result = ValidationResult(package, 'macports', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'macports', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
