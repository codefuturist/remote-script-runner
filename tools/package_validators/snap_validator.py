"""Snap package validator."""

import requests
from .base import PackageValidator, ValidationResult


class SnapValidator(PackageValidator):
    """Validates Snap packages."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'snap'

    def validate(self, package: str) -> ValidationResult:
        """Validate Snap package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            url = f"https://api.snapcraft.io/v2/snaps/info/{package}"
            headers = {'Snap-Device-Series': '16'}
            response = requests.get(url, headers=headers, timeout=15)

            if response.status_code == 200:
                result = ValidationResult(package, 'snap', 'verified',
                                         details='Found in Snap Store')
            elif response.status_code == 404:
                result = ValidationResult(package, 'snap', 'not_found',
                                         details='Not found in Snap Store')
            else:
                result = ValidationResult(package, 'snap', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'snap', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
