"""Scoop package validator."""

import requests
from .base import PackageValidator, ValidationResult


class ScoopValidator(PackageValidator):
    """Validates Scoop packages from main bucket."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'scoop'

    def validate(self, package: str) -> ValidationResult:
        """Validate Scoop package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            # Check main bucket first
            url = f"https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/{package}.json"
            response = requests.head(url, timeout=10, allow_redirects=True)

            if response.status_code == 200:
                result = ValidationResult(package, 'scoop', 'verified',
                                         details='Found in Scoop main bucket')
            elif response.status_code == 404:
                result = ValidationResult(package, 'scoop', 'not_found',
                                         details='Not found in Scoop main bucket')
            else:
                result = ValidationResult(package, 'scoop', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'scoop', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
