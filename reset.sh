#!/usr/bin/env bash

set -euo pipefail

SSH_KEY="$HOME/.ssh/team_internal"
HADOOP_DIR="/opt/hadoop-3.4.1"

NODES=(
    "10.22.0.11"
    "10.22.0.12"
    "10.22.0.13"
)

echo "WARNING: this will completely remove the Hadoop cluster."
echo "Repository and SSH keys will be preserved."
read -r -p "Type RESET to continue: " answer

if [ "$answer" != "RESET" ]; then
    echo "Reset cancelled"
    exit 1
fi

echo "=== Stopping HDFS on edge ==="

if [ -x "$HADOOP_DIR/bin/hdfs" ]; then
    "$HADOOP_DIR/bin/hdfs" --daemon stop secondarynamenode || true
    "$HADOOP_DIR/bin/hdfs" --daemon stop datanode || true
fi

echo "=== Stopping HDFS on remote nodes ==="

ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" team@10.22.0.11 "
    if [ -x '$HADOOP_DIR/bin/hdfs' ]; then
        '$HADOOP_DIR/bin/hdfs' --daemon stop namenode || true
    fi
"

for host in 10.22.0.12 10.22.0.13; do
    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" "
        if [ -x '$HADOOP_DIR/bin/hdfs' ]; then
            '$HADOOP_DIR/bin/hdfs' --daemon stop datanode || true
        fi
    "
done

echo "=== Removing Hadoop from edge ==="

sudo rm -rf "$HADOOP_DIR"
rm -rf "$HOME/hadoop-data"
rm -rf "$HOME/hadoop-log-archive"
rm -f /tmp/hadoop.tar.gz

echo "=== Removing Hadoop from remote nodes ==="

for host in "${NODES[@]}"; do
    echo "Cleaning $host"

    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" "
        sudo rm -rf '$HADOOP_DIR'
        rm -rf /home/team/hadoop-data
        rm -rf /home/team/hadoop-log-archive
        rm -f /tmp/hadoop.tar.gz
    "
done

echo "=== Removing Java from edge ==="

JAVA_PACKAGES=$(dpkg-query -W -f='${binary:Package}\n' 'openjdk-11-*' 2>/dev/null || true)

if [ -n "$JAVA_PACKAGES" ]; then
    sudo apt-get purge -y $JAVA_PACKAGES
    sudo apt-get autoremove -y
else
    echo "Java already absent on edge"
fi

echo "=== Removing Java from remote nodes ==="

for host in "${NODES[@]}"; do
    echo "Removing Java from $host"

    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" '
        JAVA_PACKAGES=$(dpkg-query -W -f="${binary:Package}\n" "openjdk-11-*" 2>/dev/null || true)

        if [ -n "$JAVA_PACKAGES" ]; then
            sudo apt-get purge -y $JAVA_PACKAGES
            sudo apt-get autoremove -y
        else
            echo "Java already absent"
        fi
    '
done

echo
echo "=== RESET FINISHED ==="
echo "Repository preserved: $HOME/hadoop-hw1"
echo "SSH keys preserved: $HOME/.ssh"
echo "Cluster machines are ready for a fresh deploy."
