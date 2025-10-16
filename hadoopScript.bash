#!/usr/bin/env bash

set -e

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run this script as root or with sudo"
  exit 1
fi
if ! command -v sudo &>/dev/null; then
  apt update && apt install -y sudo
fi
HADOOP_VERSION="3.3.6"
HADOOP_HOME="/home/hadoop/hadoop"
JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
USER_NAME="hadoop"
PASSWORD="hadoop"
installDependencies(){
  sudo apt update && sudo apt install -y openjdk-8-jdk openssh-server openssh-client || { echo Failed ; exit 1; }
}
setupSSH(){
sudo -u $USER_NAME bash <<EOF
mkdir -p /home/$USER_NAME/.ssh
ssh-keygen -t rsa -N "" -f /home/$USER_NAME/.ssh/id_rsa
cat /home/$USER_NAME/.ssh/id_rsa.pub >> /home/$USER_NAME/.ssh/authorized_keys
chmod 700 /home/$USER_NAME/.ssh
chmod 600 /home/$USER_NAME/.ssh/authorized_keys
EOF
sudo systemctl enable ssh
sudo systemctl start ssh
}
downloadHadoop(){
sudo -u $USER_NAME bash <<EOF
if ! [ -f /tmp/hadoop-${HADOOP_VERSION}.tar.gz ]; then
  wget -P /tmp/ "https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"
fi
tar -xzvf /tmp/hadoop-${HADOOP_VERSION}.tar.gz -C /home/$USER_NAME
mv /home/$USER_NAME/hadoop-${HADOOP_VERSION} /home/$USER_NAME/hadoop
EOF
sudo chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/hadoop
}

#apt update && apt install -y sudo
#install dependencies
installDependencies

#create hadoop user
if ! id -u $USER_NAME &>/dev/null; then
  sudo useradd -m -s /bin/bash $USER_NAME
  echo "$USER_NAME:$PASSWORD" | sudo chpasswd
fi
#setup ssh connection in the hadoop user
setupSSH
#Download hadoop
downloadHadoop

#clean the bashrc file
sudo -u $USER_NAME sed -i '/HADOOP_HOME/d;/JAVA_HOME/d;/HADOOP_/d' /home/$USER_NAME/.bashrc
#add some enviromental variable
cat <<EOF | sudo -u $USER_NAME tee -a /home/$USER_NAME/.bashrc >/dev/null
export JAVA_HOME=${JAVA_HOME}
export HADOOP_HOME=${HADOOP_HOME}
export HADOOP_INSTALL=\$HADOOP_HOME
export HADOOP_MAPRED_HOME=\$HADOOP_HOME
export HADOOP_COMMON_HOME=\$HADOOP_HOME
export HADOOP_HDFS_HOME=\$HADOOP_HOME
export HADOOP_YARN_HOME=\$HADOOP_HOME
export HADOOP_COMMON_LIB_NATIVE_DIR=\$HADOOP_HOME/lib/native
export PATH=\$PATH:\$HADOOP_HOME/sbin:\$HADOOP_HOME/bin
export HADOOP_OPTS='-Djava.library.path=\$HADOOP_HOME/lib/native'
EOF

#config hadoop
if grep -q "JAVA_HOME=" $HADOOP_HOME/etc/hadoop/hadoop-env.sh; then
  sudo -u $USER_NAME sed -i "/JAVA_HOME=/c\export JAVA_HOME=${JAVA_HOME}" $HADOOP_HOME/etc/hadoop/hadoop-env.sh
else
  echo "export JAVA_HOME=${JAVA_HOME}" | sudo -u $USER_NAME tee -a $HADOOP_HOME/etc/hadoop/hadoop-env.sh &>/dev/null
fi

sudo -u $USER_NAME mkdir -p /home/$USER_NAME/hadoopdata/hdfs/{namenode,datanode}

sudo -u $USER_NAME cat <<EOF > $HADOOP_HOME/etc/hadoop/core-site.xml
<configuration>
<property>
<name>fs.defaultFS</name>
<value>hdfs://localhost:9000</value>
</property>
</configuration>
EOF

sudo -u $USER_NAME cat <<EOF > $HADOOP_HOME/etc/hadoop/hdfs-site.xml
<configuration>
<property>
<name>dfs.replication</name>
<value>1</value>
</property>
<property> <name>dfs.namenode.name.dir</name>
<value>file:///home/hadoop/hadoopdata/hdfs/namenode</value>
</property>
<property>
<name>dfs.datanode.data.dir</name>
<value>file:///home/hadoop/hadoopdata/hdfs/datanode</value>
</property>
</configuration>
EOF

sudo -u $USER_NAME cat <<EOF > $HADOOP_HOME/etc/hadoop/mapred-site.xml
<configuration>
<property>
<name>yarn.app.mapreduce.am.env</name>
<value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value>
</property>
<property>
<name>mapreduce.map.env</name>
<value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value>
</property>
<property>
<name>mapreduce.reduce.env</name>
<value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value>
</property>
</configuration>
EOF

sudo -u $USER_NAME cat <<EOF > $HADOOP_HOME/etc/hadoop/yarn-site.xml
<configuration>
<property>
<name>yarn.nodemanager.aux-services</name>
<value>mapreduce_shuffle</value>
</property>
</configuration>
EOF


rm /tmp/hadoop-${HADOOP_VERSION}.tar.gz