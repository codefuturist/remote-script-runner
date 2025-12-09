# Docker Management

Docker installation and management operations.

## Quick Start

```bash
# Install Docker Engine
curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker install engine

# Check status
curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker status

# List containers
curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker ps
```

## Commands

- `install engine` - Install Docker Engine
- `status` - Show Docker status
- `ps` - List containers
- `images` - List images
- `df` - Show disk usage
- `cleanup` - Clean up unused resources

Platform support: Ubuntu, Debian, RHEL, Rocky, Alma, Fedora, Arch
