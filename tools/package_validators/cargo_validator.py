"""Cargo (crates.io) package validator."""

import requests
from .base import PackageValidator, ValidationResult


class CargoValidator(PackageValidator):
    """Validates Cargo packages from crates.io."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'cargo'

    def validate(self, package: str) -> ValidationResult:
        """Validate Cargo package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            url = f"https://crates.io/api/v1/crates/{package}"
            headers = {'User-Agent': 'remote-script-runner-package-verifier'}
            response = requests.get(url, headers=headers, timeout=10)

            if response.status_code == 200:
                result = ValidationResult(package, 'cargo', 'verified',
                                         details='Found in crates.io')
            elif response.status_code == 404:
                result = ValidationResult(package, 'cargo', 'not_found',
                                         details='Not found in crates.io')
            else:
                result = ValidationResult(package, 'cargo', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'cargo', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
