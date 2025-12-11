"""Krew kubectl plugin validator."""

import requests
from .base import PackageValidator, ValidationResult


class KrewValidator(PackageValidator):
    """Validates Krew kubectl plugins."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'krew'

    def validate(self, package: str) -> ValidationResult:
        """Validate Krew plugin."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            # Check krew-index repository
            url = f"https://raw.githubusercontent.com/kubernetes-sigs/krew-index/master/plugins/{package}.yaml"
            response = requests.head(url, timeout=10, allow_redirects=True)

            if response.status_code == 200:
                result = ValidationResult(package, 'krew', 'verified',
                                         details='Found in krew-index')
            elif response.status_code == 404:
                result = ValidationResult(package, 'krew', 'not_found',
                                         details='Not found in krew-index')
            else:
                result = ValidationResult(package, 'krew', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'krew', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
