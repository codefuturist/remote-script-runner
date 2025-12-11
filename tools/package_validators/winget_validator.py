"""Winget package validator."""

import requests
import os
from .base import PackageValidator, ValidationResult


class WingetValidator(PackageValidator):
    """Validates Winget packages from microsoft/winget-pkgs repository."""

    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'winget'
        self._rate_limited = False

    def _package_id_to_path(self, package_id: str) -> str:
        """Convert package ID to manifest path."""
        # Example: Kubernetes.kubectl -> manifests/k/Kubernetes/kubectl
        parts = package_id.split('.')
        if len(parts) >= 2:
            first_letter = parts[0][0].lower()
            publisher = parts[0]
            name = '.'.join(parts[1:])
            return f"manifests/{first_letter}/{publisher}/{name}"
        return None

    def validate(self, package: str) -> ValidationResult:
        """Validate Winget package."""
        cached = self.get_cached(package)
        if cached:
            return cached

        # If we've been rate limited, mark as unverifiable
        if self._rate_limited:
            result = ValidationResult(package, 'winget', 'unverifiable',
                                     details='GitHub API rate limited')
            self.set_cached(result)
            return result

        try:
            path = self._package_id_to_path(package)
            if not path:
                result = ValidationResult(package, 'winget', 'error',
                                         details='Invalid package ID format')
            else:
                # Check if directory exists in GitHub repo
                url = f"https://api.github.com/repos/microsoft/winget-pkgs/contents/{path}"
                headers = {
                    'Accept': 'application/vnd.github.v3+json',
                    'User-Agent': 'remote-script-runner-package-verifier'
                }

                # Add GitHub token if available
                github_token = os.environ.get('GITHUB_TOKEN')
                if github_token:
                    headers['Authorization'] = f'token {github_token}'

                response = requests.get(url, headers=headers, timeout=15)

                if response.status_code == 200:
                    result = ValidationResult(package, 'winget', 'verified',
                                             details='Found in winget-pkgs repository')
                elif response.status_code == 404:
                    result = ValidationResult(package, 'winget', 'not_found',
                                             details='Not found in winget-pkgs repository')
                elif response.status_code == 403:
                    # Rate limited
                    self._rate_limited = True
                    result = ValidationResult(package, 'winget', 'unverifiable',
                                             details='GitHub API rate limited (set GITHUB_TOKEN env var)')
                else:
                    result = ValidationResult(package, 'winget', 'error',
                                             details=f'HTTP {response.status_code}')
        except Exception as e:
            result = ValidationResult(package, 'winget', 'error',
                                     details=f'Validation error: {str(e)}')

        self.set_cached(result)
        return result
