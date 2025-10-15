#!/usr/bin/env bash

installDependencies(){
  sudo apt update && sudo apt install -y openjdk-8-jdk openssh-server openssh-client || { echo Failed ; exit 1; }
}
setupSSH(){
sudo -u hadoop bash <<EOF
mkdir -p ~/.ssh
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
EOF
}
downloadHadoop(){
  wget -P /tmp/ https://dlcdn.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
  tar -xzvf /tmp/hadoop-3.3.6.tar.gz -C /tmp/
  mv hadoop-3.3.6 hadoop
}

#apt update && apt install -y sudo
#install dependencies
installDependencies
#Download hadoop
downloadHadoop
#add some enviromental variable
HADOOP_TEMP=/tmp/hadoop
HADOOP_HOME="/home/hadoop/hadoop"
JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
USER_NAME="hadoop"
PASSWORD="hadoop"

sudo useradd -m -s /bin/bash $USER_NAME
echo "$USER_NAME:$PASSWORD" | sudo chpasswd
#setup ssh connection in the hadoop user
setupSSH

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
if grep -q "JAVA_HOME=" $HADOOP_TEMP/etc/hadoop/hadoop-env.sh; then
  sed -i "/JAVA_HOME=/c\export JAVA_HOME=${JAVA_HOME}" $HADOOP_TEMP/etc/hadoop/hadoop-env.sh
else
  echo "export JAVA_HOME=${JAVA_HOME}" >> $HADOOP_TEMP/etc/hadoop/hadoop-env.sh
fi

mkdir -p /home/$USER_NAME/hadoopdata/hdfs/{namenode,datanode}

cat <<EOF > $HADOOP_TEMP/etc/hadoop/core-site.xml
<configuration>
<property>
<name>fs.defaultFS</name>
<value>hdfs://localhost:9000</value>
</property>
</configuration>
EOF

cat <<EOF > $HADOOP_TEMP/etc/hadoop/hdfs-site.xml
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

cat <<EOF > $HADOOP_TEMP/etc/hadoop/mapred-site.xml
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

cat <<EOF > $HADOOP_TEMP/etc/hadoop/yarn-site.xml
<configuration>
<property>
<name>yarn.nodemanager.aux-services</name>
<value>mapreduce_shuffle</value>
</property>
</configuration>
EOF

cp -r $HADOOP_TEMP $HADOOP_HOME
chown -R hadoop:hadoop /home/hadoop/hadoop
rm -rf $HADOOP_TEMP
