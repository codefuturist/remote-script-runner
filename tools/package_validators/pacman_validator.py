"""Pacman (Arch Linux) package validator."""

import requests
from .base import PackageValidator, ValidationResult


class PacmanValidator(PackageValidator):
    """Validates Arch Linux packages."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'pacman'

    def validate(self, package: str) -> ValidationResult:
        """Validate Arch Linux package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            # Arch Linux package search API
            url = f"https://archlinux.org/packages/search/json/?name={package}"
            headers = {'User-Agent': 'remote-script-runner-package-verifier'}
            response = requests.get(url, headers=headers, timeout=15)

            if response.status_code == 200:
                data = response.json()
                if data.get('results'):
                    result = ValidationResult(package, 'pacman', 'verified',
                                             details='Found in Arch Linux repositories')
                else:
                    result = ValidationResult(package, 'pacman', 'not_found',
                                             details='Not found in Arch Linux repositories')
            else:
                result = ValidationResult(package, 'pacman', 'error',
                                         details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'pacman', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
