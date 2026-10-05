#!/usr/bin/env bash

set -euo pipefail

SSH_KEY="$HOME/.ssh/team_internal"

NODES=(
    "10.22.0.11"
    "10.22.0.12"
    "10.22.0.13"
)

echo "=== Installing Java on edge ==="

if command -v java >/dev/null 2>&1; then
    echo "Java already installed on edge"
else
    sudo apt-get update
    sudo apt-get install -y openjdk-11-jdk
fi

echo "=== Installing Java on remote nodes ==="

for host in "${NODES[@]}"; do
    echo "Checking $host"

    ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" '
        if command -v java >/dev/null 2>&1; then
            echo "Java already installed"
        else
            sudo apt-get update
            sudo apt-get install -y openjdk-11-jdk
        fi
    '
done

echo "=== Java installation finished ==="
