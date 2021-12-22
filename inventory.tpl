---
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: '~/.ssh/maximrunv3.pem'
    ansible_become: true
  children:
    kube:
      children:
        masters:
          hosts:
%{ for host in masters ~}
            ${host.name}:
              ansible_host: ${host.ip}
%{ endfor ~}
        workers:
          hosts:
%{ for host in workers ~}
            ${host.name}:
              ansible_host: ${host.ip}
%{ endfor ~}
        # ceph:
        #   hosts:
        #     fdstorage01:
        #       ansible_host: 10.10.128.17


              


