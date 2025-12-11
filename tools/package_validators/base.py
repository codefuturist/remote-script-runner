"""Base validator class for package verification."""

from abc import ABC, abstractmethod
from typing import Dict, Optional
import time


class ValidationResult:
    """Result of package validation."""

    def __init__(self, package: str, manager: str, status: str,
                 details: Optional[str] = None, suggestion: Optional[str] = None):
        self.package = package
        self.manager = manager
        self.status = status  # verified, not_found, unverifiable, error
        self.details = details
        self.suggestion = suggestion
        self.timestamp = time.time()

    def to_dict(self) -> Dict:
        return {
            'package': self.package,
            'manager': self.manager,
            'status': self.status,
            'details': self.details,
            'suggestion': self.suggestion,
            'timestamp': self.timestamp
        }


class PackageValidator(ABC):
    """Abstract base class for package validators."""

    def __init__(self, cache: Optional[Dict] = None):
        self.cache = cache if cache is not None else {}
        self.manager_name = self.__class__.__name__.replace('Validator', '').lower()

    @abstractmethod
    def validate(self, package: str) -> ValidationResult:
        """
        Validate if a package exists.

        Args:
            package: Package name to validate

        Returns:
            ValidationResult with status and details
        """
        pass

    def get_cache_key(self, package: str) -> str:
        """Generate cache key for package."""
        return f"{self.manager_name}:{package}"

    def get_cached(self, package: str) -> Optional[ValidationResult]:
        """Get cached validation result if available and not expired."""
        cache_key = self.get_cache_key(package)
        if cache_key in self.cache:
            cached = self.cache[cache_key]
            # Cache valid for 24 hours
            if time.time() - cached.get('timestamp', 0) < 86400:
                return ValidationResult(
                    package=cached['package'],
                    manager=cached['manager'],
                    status=cached['status'],
                    details=cached.get('details'),
                    suggestion=cached.get('suggestion')
                )
        return None

    def set_cached(self, result: ValidationResult):
        """Cache validation result."""
        cache_key = self.get_cache_key(result.package)
        self.cache[cache_key] = result.to_dict()
