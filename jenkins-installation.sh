Jenkins install steps:

sudo apt update
sudo apt install fontconfig openjdk-17-jre -y
java -version
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
sudo apt-get install jenkins -y
sudo apt install docker.io -y
sudo chmod 666 /var/run/docker.sock
sudo chown jenkins /var/run/docker.sock
sudo chown $USER /var/run/docker.sock

install Jenkins using container:
docker run -d --name jenkins -p 8080:8080 jenkins/jenkins

Removal:
sudo apt-get remove jenkins
sudo apt-get remove --auto-remove jenkins

install sonarqube:
docker run -d -p 9000:9000 sonarqube:lts-community

jdk-removal:
sudo apt-get purge openjdk-*     # Remove OpenJDK
sudo apt-get purge oracle-java*  # Remove Oracle JDK (if installed)
sudo apt-get autoremove          # Remove dependencies that are no longer needed

install 1.8 jdk and set environment variables:
sudo apt-get update
sudo apt-get install openjdk-8-jdk
echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc


939ddde6e6a74d8d8e62f7ded9c9eb85