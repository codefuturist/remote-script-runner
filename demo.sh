#!/usr/bin/env bash

# Demo script showcasing various remote-runner.sh use cases

set -euo pipefail

echo "=== Remote Script Runner Demo ==="
echo

echo "1. Basic command execution (dry-run):"
echo "   ./remote-runner.sh -h server.example.com -c 'uptime' -n"
./remote-runner.sh -h server.example.com -c "uptime" -n
echo

echo "2. Execute command with specific SSH key and user (dry-run):"
echo "   ./remote-runner.sh -h server.example.com -u deploy -i ~/.ssh/id_ed25519 -c 'systemctl status nginx' -n"
./remote-runner.sh -h server.example.com -u deploy -i ~/.ssh/id_ed25519 -c "systemctl status nginx" -n
echo

echo "3. Execute local script on remote server (dry-run):"
echo "   ./remote-runner.sh -h server.example.com -f ./example-deploy.sh -n"
./remote-runner.sh -h server.example.com -f ./example-deploy.sh -n
echo

echo "4. Connect through jump host (dry-run):"
echo "   ./remote-runner.sh -h internal.server -j bastion.example.com -c 'hostname' -n"
./remote-runner.sh -h internal.server -j bastion.example.com -c "hostname" -n
echo

echo "5. Execute on multiple hosts in parallel (dry-run):"
echo "   ./remote-runner.sh -h 'web1.example.com,web2.example.com,web3.example.com' --parallel --max-jobs 2 -c 'systemctl restart nginx' -n"
./remote-runner.sh -h "web1.example.com,web2.example.com,web3.example.com" --parallel --max-jobs 2 -c "systemctl restart nginx" -n
echo

echo "6. Using custom timeout and retry settings (dry-run):"
echo "   ./remote-runner.sh -h slow.server.com -t 60 -r 5 -d 10 -c 'curl -f http://api.example.com/health' -n -v"
./remote-runner.sh -h slow.server.com -t 60 -r 5 -d 10 -c "curl -f http://api.example.com/health" -n -v
echo

echo "=== Demo completed ==="
echo
echo "Note: All commands were run in dry-run mode (-n flag)"
echo "Remove the -n flag to execute commands for real"
