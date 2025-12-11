"""Homebrew formula and cask validator."""

import requests
from typing import Dict, Set
from .base import PackageValidator, ValidationResult


class BrewValidator(PackageValidator):
    """Validates Homebrew formulas and casks."""

    def __init__(self, cache: Dict = None):
        super().__init__(cache)
        self._formulas: Set[str] = set()
        self._casks: Set[str] = set()
        self._loaded = False

    def _load_catalog(self):
        """Load full Homebrew catalog."""
        if self._loaded:
            return

        try:
            # Load formulas
            response = requests.get('https://formulae.brew.sh/api/formula.json', timeout=30)
            if response.status_code == 200:
                formulas = response.json()
                self._formulas = {f['name'] for f in formulas}
                # Also include full_name for taps
                self._formulas.update({f.get('full_name', f['name']) for f in formulas})

            # Load casks
            response = requests.get('https://formulae.brew.sh/api/cask.json', timeout=30)
            if response.status_code == 200:
                casks = response.json()
                self._casks = {c['token'] for c in casks}
                self._casks.update({c.get('full_token', c['token']) for c in casks})

            self._loaded = True
        except Exception as e:
            print(f"Warning: Failed to load Homebrew catalog: {e}")

    def validate(self, package: str) -> ValidationResult:
        """Validate Homebrew package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        self._load_catalog()

        # Check if it's a formula
        if package in self._formulas:
            result = ValidationResult(package, 'brew', 'verified',
                                     details='Found in Homebrew formulas')
        # Check if it might be a cask
        elif package in self._casks:
            result = ValidationResult(package, 'brew', 'verified',
                                     details='Found in Homebrew casks',
                                     suggestion='Consider using brew_cask manager')
        else:
            result = ValidationResult(package, 'brew', 'not_found',
                                     details='Not found in Homebrew formulas or casks')

        self.set_cached(result)
        return result


class BrewCaskValidator(PackageValidator):
    """Validates Homebrew casks."""

    def __init__(self, cache: Dict = None):
        super().__init__(cache)
        self.manager_name = 'brew_cask'
        self._casks: Set[str] = set()
        self._loaded = False

    def _load_catalog(self):
        """Load Homebrew cask catalog."""
        if self._loaded:
            return

        try:
            response = requests.get('https://formulae.brew.sh/api/cask.json', timeout=30)
            if response.status_code == 200:
                casks = response.json()
                self._casks = {c['token'] for c in casks}
                self._casks.update({c.get('full_token', c['token']) for c in casks})
            self._loaded = True
        except Exception as e:
            print(f"Warning: Failed to load Homebrew cask catalog: {e}")

    def validate(self, package: str) -> ValidationResult:
        """Validate Homebrew cask."""
        cached = self.get_cached(package)
        if cached:
            return cached

        self._load_catalog()

        if package in self._casks:
            result = ValidationResult(package, 'brew_cask', 'verified',
                                     details='Found in Homebrew casks')
        else:
            result = ValidationResult(package, 'brew_cask', 'not_found',
                                     details='Not found in Homebrew casks')

        self.set_cached(result)
        return result
