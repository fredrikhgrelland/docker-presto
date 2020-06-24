Vagrant.configure("2") do |config|
  config.vm.box = "fredrikhgrelland/hashistack"
  config.vm.network "private_network", ip: "10.0.3.10"
  config.vm.box_version = "~> 0.1"

  # Hashicorp consul ui
  config.vm.network "forwarded_port", guest: 8500, host: 8500, host_ip: "127.0.0.1"

  # Hashicorp nomad ui
  config.vm.network "forwarded_port", guest: 4646, host: 4646, host_ip: "127.0.0.1"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 16000
    vb.cpus = 4
  end

  #Override nomad in order to run plugins.
  config.vm.provision "shell", inline: "cp /vagrant/conf/nomad/config-override.hcl /etc/nomad.d/config-override.hcl"

  # running playbook that starts consul, vault, and nomad
  config.vm.provision "ansible_local" do |startup|
    run = "always"
    startup.playbook = "/etc/ansible/startup.yml"
  end
  config.vm.provision "ansible_local" do |ansible|
    ansible.playbook = "./test/ansible/playbook.yml"

    # default mode `dev`
    ansible.extra_vars = {
        mode: 'dev'
    }

    # use to override default mode (e.g. test mode)
    ansible.raw_arguments = Shellwords.shellsplit(ENV['ANSIBLE_ARGS']) if ENV['ANSIBLE_ARGS']
  end
end
