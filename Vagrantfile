# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ailispaw/barge"

  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
  end

  ip = "172.17.8.102"
  config.vm.network :private_network, ip: ip

  config.vm.synced_folder ".", "/home/bargee/circleci-base", 
    type: "nfs",
    mount_options: ["nolock", "vers=3", "udp", "noatime", "actimeo=1"]

  config.vm.provision :shell, path: "dev/init", privileged: false
end