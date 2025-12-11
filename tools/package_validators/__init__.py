"""Package validators for different package managers."""

from .base import PackageValidator, ValidationResult
from .brew_validator import BrewValidator
from .npm_validator import NpmValidator
from .pypi_validator import PyPiValidator
from .cargo_validator import CargoValidator
from .choco_validator import ChocoValidator
from .winget_validator import WingetValidator
from .scoop_validator import ScoopValidator
from .krew_validator import KrewValidator
from .pacman_validator import PacmanValidator
from .snap_validator import SnapValidator
from .macports_validator import MacPortsValidator
from .fallback_validator import FallbackValidator

__all__ = [
    'PackageValidator',
    'ValidationResult',
    'BrewValidator',
    'NpmValidator',
    'PyPiValidator',
    'CargoValidator',
    'ChocoValidator',
    'WingetValidator',
    'ScoopValidator',
    'KrewValidator',
    'PacmanValidator',
    'SnapValidator',
    'MacPortsValidator',
    'FallbackValidator',
]
