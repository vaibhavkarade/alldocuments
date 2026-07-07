sudo apt-add-repository ppa:ansible/ansible
sudo apt update
sudo apt install ansible









 clear
    2  sudo apt-add-repository ppa:ansible/ansible
    3  sudo apt update
    4  sudo apt install ansible
    5  ansible --version
    6  clear
    7  cd /etc/ansible/
    8  ls
    9  sudo vim hosts
172.191.106.233  ansible_ssh_user=bunty ansible_private_key_file=key
172.191.106.234  ansible_ssh_user=bunty ansible_private_key_file=key
   10  ansible all -m ping
   11  clear
   12  ansible all -m ping.
   13  sudo vim key- paste the pem key of client1 in key file
   14  cat key
   15  clear
   16  ls
   17  ls -l
   18  chmod 600 key
provide access to created key for user: sudo chown $USER key
   19  ls -l
   20  ansible all -m ping
   21  history