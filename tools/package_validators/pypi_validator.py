"""PyPI package validator."""

import requests
from .base import PackageValidator, ValidationResult


class PyPiValidator(PackageValidator):
    """Validates PyPI packages."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'pip'

    def validate(self, package: str) -> ValidationResult:
        """Validate PyPI package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            # Use HEAD request for efficiency
            url = f"https://pypi.org/pypi/{package}/json"
            response = requests.head(url, timeout=10, allow_redirects=True)

            if response.status_code == 200:
                result = ValidationResult(package, 'pip', 'verified',
                                         details='Found in PyPI')
            elif response.status_code == 404:
                result = ValidationResult(package, 'pip', 'not_found',
                                         details='Not found in PyPI')
            else:
                result = ValidationResult(package, 'pip', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'pip', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
