"""NPM package validator."""

import requests
from .base import PackageValidator, ValidationResult


class NpmValidator(PackageValidator):
    """Validates NPM packages."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'npm'

    def validate(self, package: str) -> ValidationResult:
        """Validate NPM package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            # Use HEAD request for efficiency
            url = f"https://registry.npmjs.org/{package}"
            response = requests.head(url, timeout=10, allow_redirects=True)

            if response.status_code == 200:
                result = ValidationResult(package, 'npm', 'verified',
                                         details='Found in NPM registry')
            elif response.status_code == 404:
                result = ValidationResult(package, 'npm', 'not_found',
                                         details='Not found in NPM registry')
            else:
                result = ValidationResult(package, 'npm', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'npm', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
