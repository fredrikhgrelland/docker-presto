Vagrant.configure("2") do |config|
    config.vm.box = "fredrikhgrelland/hashistack"
    config.vm.box_version = "~> 0.2"
    config.vm.provider "virtualbox" do |vb|
        vb.linked_clone = true
        vb.memory = 12000
        vb.cpus = 3
    end
    config.vm.provision "ansible_local" do |startup|
        run = "always"
        startup.playbook = "/vagrant/ansible/playbook.yml"
        startup.raw_arguments = Shellwords.shellsplit(ENV['ANSIBLE_ARGS']) if ENV['ANSIBLE_ARGS']
    end
end
