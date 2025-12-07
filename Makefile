# =============================================================================
# Remote Script Runner - Makefile
# =============================================================================
#
# Common development tasks for the project.
#
# Usage:
#   make help        Show this help message
#   make all         Run all quality checks (lint, test, validate)
#   make lint        Run ShellCheck on all scripts
#   make format      Format all shell scripts with shfmt
#   make test        Run all tests
#   make validate    Validate registry and script headers
#   make install     Install development dependencies
#   make clean       Clean temporary files
#
# =============================================================================

.PHONY: all help lint format test test-unit test-integration validate install clean setup-hooks check

# Default target
all: lint test validate

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

# Directories
SCRIPTS_DIR := scripts/bash
LIB_DIR := lib
TEST_DIR := test
TOOLS_DIR := tools

# Files to lint/format
SHELL_FILES := rsr $(wildcard $(SCRIPTS_DIR)/*.sh) $(wildcard $(LIB_DIR)/*.sh) $(wildcard $(TOOLS_DIR)/*.sh)
BATS_FILES := $(wildcard $(TEST_DIR)/unit/*.bats) $(wildcard $(TEST_DIR)/integration/*.bats)

# =============================================================================
# Help
# =============================================================================

help:
	@echo ""
	@echo "$(BLUE)Remote Script Runner - Development Tasks$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  make $(GREEN)<target>$(NC)"
	@echo ""
	@echo "$(YELLOW)Targets:$(NC)"
	@echo "  $(GREEN)all$(NC)              Run all quality checks (lint, test, validate)"
	@echo "  $(GREEN)lint$(NC)             Run ShellCheck on all shell scripts"
	@echo "  $(GREEN)format$(NC)           Format all shell scripts with shfmt"
	@echo "  $(GREEN)format-check$(NC)     Check formatting without making changes"
	@echo "  $(GREEN)test$(NC)             Run all tests (unit + integration)"
	@echo "  $(GREEN)test-unit$(NC)        Run only unit tests"
	@echo "  $(GREEN)test-integration$(NC) Run only integration tests"
	@echo "  $(GREEN)test-verbose$(NC)     Run all tests with verbose output"
	@echo "  $(GREEN)validate$(NC)         Validate registry.json and script headers"
	@echo "  $(GREEN)install$(NC)          Install development dependencies"
	@echo "  $(GREEN)setup-hooks$(NC)      Install pre-commit hooks"
	@echo "  $(GREEN)clean$(NC)            Clean temporary files and caches"
	@echo "  $(GREEN)check$(NC)            Quick check (syntax only, fast)"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make                  # Run all checks (same as 'make all')"
	@echo "  make lint test        # Run linting then tests"
	@echo "  make format           # Auto-format all scripts"
	@echo ""

# =============================================================================
# Linting
# =============================================================================

lint: lint-shellcheck lint-syntax
	@echo "$(GREEN)✓ All linting passed$(NC)"

lint-shellcheck:
	@echo "$(BLUE)▸ Running ShellCheck...$(NC)"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x $(SHELL_FILES) && echo "$(GREEN)✓ ShellCheck passed$(NC)"; \
	else \
		echo "$(YELLOW)⚠ ShellCheck not installed. Install with: brew install shellcheck$(NC)"; \
	fi

lint-syntax:
	@echo "$(BLUE)▸ Checking shell syntax...$(NC)"
	@for file in $(SHELL_FILES); do \
		if head -1 "$$file" | grep -q "bash"; then \
			bash -n "$$file" || exit 1; \
		else \
			sh -n "$$file" || exit 1; \
		fi; \
	done
	@echo "$(GREEN)✓ Syntax check passed$(NC)"

# =============================================================================
# Formatting
# =============================================================================

format:
	@echo "$(BLUE)▸ Formatting shell scripts with shfmt...$(NC)"
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -i 4 -ci -bn -sr -w $(SHELL_FILES); \
		echo "$(GREEN)✓ Formatting complete$(NC)"; \
	else \
		echo "$(YELLOW)⚠ shfmt not installed. Install with: brew install shfmt$(NC)"; \
		exit 1; \
	fi

format-check:
	@echo "$(BLUE)▸ Checking shell script formatting...$(NC)"
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -i 4 -ci -bn -sr -d $(SHELL_FILES) && echo "$(GREEN)✓ Formatting OK$(NC)"; \
	else \
		echo "$(YELLOW)⚠ shfmt not installed. Install with: brew install shfmt$(NC)"; \
	fi

# =============================================================================
# Testing
# =============================================================================

test:
	@echo "$(BLUE)▸ Running all tests...$(NC)"
	@./test/run_tests.sh

test-unit:
	@echo "$(BLUE)▸ Running unit tests...$(NC)"
	@./test/run_tests.sh --unit

test-integration:
	@echo "$(BLUE)▸ Running integration tests...$(NC)"
	@./test/run_tests.sh --integration

test-verbose:
	@echo "$(BLUE)▸ Running all tests (verbose)...$(NC)"
	@./test/run_tests.sh --verbose

test-quick:
	@echo "$(BLUE)▸ Running quick syntax check...$(NC)"
	@bash -n rsr
	@for script in $(SCRIPTS_DIR)/*.sh; do bash -n "$$script"; done
	@echo "$(GREEN)✓ Quick check passed$(NC)"

# =============================================================================
# Validation
# =============================================================================

validate:
	@echo "$(BLUE)▸ Validating registry and scripts...$(NC)"
	@./tools/validate.sh

validate-strict:
	@echo "$(BLUE)▸ Validating registry and scripts (strict mode)...$(NC)"
	@./tools/validate.sh --strict

# =============================================================================
# Development Setup
# =============================================================================

install: install-deps setup-hooks
	@echo "$(GREEN)✓ Development environment ready$(NC)"

install-deps:
	@echo "$(BLUE)▸ Installing development dependencies...$(NC)"
ifeq ($(shell uname -s),Darwin)
	@echo "  Installing via Homebrew..."
	@brew install shellcheck shfmt bats-core jq pre-commit || true
else
	@echo "  Installing via apt..."
	@sudo apt-get update && sudo apt-get install -y shellcheck jq || true
	@echo "  Note: Install shfmt manually: https://github.com/mvdan/sh/releases"
	@pip install pre-commit || pip3 install pre-commit || true
endif
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

setup-hooks:
	@echo "$(BLUE)▸ Setting up pre-commit hooks...$(NC)"
	@if command -v pre-commit >/dev/null 2>&1; then \
		pre-commit install; \
		echo "$(GREEN)✓ Pre-commit hooks installed$(NC)"; \
	else \
		echo "$(YELLOW)⚠ pre-commit not installed. Install with: pip install pre-commit$(NC)"; \
	fi

# Initialize submodules for BATS
init-submodules:
	@echo "$(BLUE)▸ Initializing git submodules...$(NC)"
	@git submodule update --init --recursive
	@echo "$(GREEN)✓ Submodules initialized$(NC)"

# =============================================================================
# Cleanup
# =============================================================================

clean:
	@echo "$(BLUE)▸ Cleaning temporary files...$(NC)"
	@rm -rf test-results/ coverage/ *.log .tmp/
	@find . -name "*.tmp" -delete
	@find . -name "*.temp" -delete
	@find . -name ".DS_Store" -delete
	@echo "$(GREEN)✓ Clean complete$(NC)"

# =============================================================================
# Quick Check (for CI or fast feedback)
# =============================================================================

check: lint-syntax validate
	@echo "$(GREEN)✓ Quick check passed$(NC)"

# =============================================================================
# CI Target (used by GitHub Actions)
# =============================================================================

ci: lint test validate
	@echo "$(GREEN)✓ CI checks passed$(NC)"

