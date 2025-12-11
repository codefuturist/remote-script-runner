"""Fallback validator for package managers without public APIs."""

from .base import PackageValidator, ValidationResult


class FallbackValidator(PackageValidator):
    """Marks packages as unverifiable for managers without public APIs."""

    UNVERIFIABLE_MANAGERS = {
        'apt': 'No reliable public API (repo-dependent)',
        'dnf': 'No reliable public API (repo-dependent)',
        'yum': 'No reliable public API (repo-dependent)',
        'zypper': 'No reliable public API (repo-dependent)',
        'pipx': 'Uses PyPI (verify with pip validator)',
    }

    def __init__(self, manager: str, cache=None):
        super().__init__(cache)
        self.manager_name = manager
        self.reason = self.UNVERIFIABLE_MANAGERS.get(manager, 'No public API available')

    def validate(self, package: str) -> ValidationResult:
        """Mark package as unverifiable."""
        cached = self.get_cached(package)
        if cached:
            return cached

        result = ValidationResult(
            package,
            self.manager_name,
            'unverifiable',
            details=self.reason
        )

        self.set_cached(result)
        return result
