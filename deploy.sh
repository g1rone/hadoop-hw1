#!/usr/bin/env bash

set -euo pipefail

SSH_KEY="$HOME/.ssh/team_internal"
HADOOP_VERSION="3.4.1"
HADOOP_DIR="/opt/hadoop-$HADOOP_VERSION"
HADOOP_URL="https://downloads.apache.org/hadoop/core/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz"
JAVA_HOME_PATH="/usr/lib/jvm/java-11-openjdk-amd64"
HADOOP_ENV="$HADOOP_DIR/etc/hadoop/hadoop-env.sh"
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


echo "=== Preparing Hadoop log directories ==="

sudo mkdir -p "$HADOOP_DIR/logs"
sudo chown -R team:team "$HADOOP_DIR/logs"

for host in "${NODES[@]}"; do
    echo "Preparing logs on $host"

    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" "
        sudo mkdir -p '$HADOOP_DIR/logs'
        sudo chown -R team:team '$HADOOP_DIR/logs'
    "
done

echo "=== Hadoop log directories prepared ==="



echo "=== Configuring JAVA_HOME for Hadoop on edge ==="

JAVA_HOME_PATH=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
HADOOP_ENV="$HADOOP_DIR/etc/hadoop/hadoop-env.sh"

if grep -q '^export JAVA_HOME=' "$HADOOP_ENV"; then
    sudo sed -i "s|^export JAVA_HOME=.*|export JAVA_HOME=$JAVA_HOME_PATH|" "$HADOOP_ENV"
else
    echo "export JAVA_HOME=$JAVA_HOME_PATH" | sudo tee -a "$HADOOP_ENV" >/dev/null
fi

echo "JAVA_HOME set to $JAVA_HOME_PATH on edge"


echo "=== Configuring JAVA_HOME on edge ==="

if grep -q '^export JAVA_HOME=' "$HADOOP_ENV"; then
    sudo sed -i "s|^export JAVA_HOME=.*|export JAVA_HOME=$JAVA_HOME_PATH|" "$HADOOP_ENV"
else
    echo "export JAVA_HOME=$JAVA_HOME_PATH" | sudo tee -a "$HADOOP_ENV" >/dev/null
fi

echo "=== Configuring JAVA_HOME on remote nodes ==="

for host in "${NODES[@]}"; do
    echo "Configuring $host"

    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" "
        if grep -q '^export JAVA_HOME=' '$HADOOP_ENV'; then
            sudo sed -i 's|^export JAVA_HOME=.*|export JAVA_HOME=$JAVA_HOME_PATH|' '$HADOOP_ENV'
        else
            echo 'export JAVA_HOME=$JAVA_HOME_PATH' | sudo tee -a '$HADOOP_ENV' >/dev/null
        fi
    "
done

echo "=== JAVA_HOME configuration finished ==="



echo "=== Deploying Hadoop configuration on edge ==="

sudo cp config/core-site.xml "$HADOOP_DIR/etc/hadoop/core-site.xml"
sudo cp config/hdfs-site.xml "$HADOOP_DIR/etc/hadoop/hdfs-site.xml"
sudo cp config/workers "$HADOOP_DIR/etc/hadoop/workers"

echo "=== Deploying Hadoop configuration on remote nodes ==="

for host in "${NODES[@]}"; do
    echo "Configuring $host"

    scp -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" config/core-site.xml config/hdfs-site.xml config/workers "team@$host:/tmp/"

    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" "
        sudo cp /tmp/core-site.xml '$HADOOP_DIR/etc/hadoop/core-site.xml'
        sudo cp /tmp/hdfs-site.xml '$HADOOP_DIR/etc/hadoop/hdfs-site.xml'
        sudo cp /tmp/workers '$HADOOP_DIR/etc/hadoop/workers'

        rm /tmp/core-site.xml
        rm /tmp/hdfs-site.xml
        rm /tmp/workers
    "
done

echo "=== Hadoop configuration deployed ==="



echo "=== Creating HDFS directories ==="

mkdir -p /home/team/hadoop-data/datanode
mkdir -p /home/team/hadoop-data/secondary

ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" team@10.22.0.11 \
    'mkdir -p /home/team/hadoop-data/namenode'

for host in 10.22.0.12 10.22.0.13; do
    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" \
        'mkdir -p /home/team/hadoop-data/datanode'
done

echo "=== HDFS directories created ==="


echo "=== Checking NameNode format ==="

ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" team@10.22.0.11 "
    if [ -f /home/team/hadoop-data/namenode/current/VERSION ]; then
        echo 'NameNode already formatted'
    else
        echo 'Formatting NameNode...'
        '$HADOOP_DIR/bin/hdfs' namenode -format -nonInteractive
    fi
"

echo "=== NameNode format checked ==="



echo "=== Starting HDFS ==="

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" team@10.22.0.11 "jps | awk '{print \$2}' | grep -qx NameNode"; then
    echo "Starting NameNode on 10.22.0.11"
    ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" team@10.22.0.11 "'$HADOOP_DIR/bin/hdfs' --daemon start namenode"
else
    echo "NameNode already running"
fi

if ! jps | awk '{print $2}' | grep -qx DataNode; then
    echo "Starting DataNode on edge"
    "$HADOOP_DIR/bin/hdfs" --daemon start datanode
else
    echo "DataNode already running on edge"
fi

for host in 10.22.0.12 10.22.0.13; do
    if ! ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" "jps | awk '{print \$2}' | grep -qx DataNode"; then
        echo "Starting DataNode on $host"
        ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$SSH_KEY" "team@$host" "'$HADOOP_DIR/bin/hdfs' --daemon start datanode"
    else
        echo "DataNode already running on $host"
    fi
done

if ! jps | awk '{print $2}' | grep -qx SecondaryNameNode; then
    echo "Starting SecondaryNameNode on edge"
    "$HADOOP_DIR/bin/hdfs" --daemon start secondarynamenode
else
    echo "SecondaryNameNode already running"
fi

echo "=== HDFS started ==="
