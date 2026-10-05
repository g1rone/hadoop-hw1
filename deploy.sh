#!/usr/bin/env bash

set -euo pipefail

SSH_KEY="$HOME/.ssh/team_internal"
HADOOP_VERSION="3.4.1"
HADOOP_DIR="/opt/hadoop-$HADOOP_VERSION"
HADOOP_URL="https://downloads.apache.org/hadoop/core/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz"
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

    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" '
        if command -v java >/dev/null 2>&1; then
            echo "Java already installed"
        else
            sudo apt-get update
            sudo apt-get install -y openjdk-11-jdk
        fi
    '
done

echo "=== Java installation finished ==="


echo "=== Installing Hadoop on edge ==="

if [ -x "$HADOOP_DIR/bin/hadoop" ]; then
    echo "Hadoop already installed on edge"
else
    wget --show-progress "$HADOOP_URL" -O /tmp/hadoop.tar.gz
    sudo tar -xzf /tmp/hadoop.tar.gz -C /opt
    rm /tmp/hadoop.tar.gz
fi

echo "=== Installing Hadoop on remote nodes ==="

for host in "${NODES[@]}"; do
    echo "Checking $host"

    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" "
        if [ -x '$HADOOP_DIR/bin/hadoop' ]; then
            echo 'Hadoop already installed'
        else
            wget --show-progress '$HADOOP_URL' -O /tmp/hadoop.tar.gz
            sudo tar -xzf /tmp/hadoop.tar.gz -C /opt
            rm /tmp/hadoop.tar.gz
        fi
    "
done

echo "=== Hadoop installation finished ==="
