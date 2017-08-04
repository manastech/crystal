# -*- mode: ruby -*-
# vi: set ft=ruby :

clone_crystal_from_vagrant = lambda do |config|
  config.vm.provision :shell, privileged: false, inline: %(
    git clone /vagrant crystal
  )
end

Vagrant.configure("2") do |config|
  %w(precise trusty xenial).product([32, 64]).each do |dist, bits|
    box_name = "#{dist}#{bits}"

    config.vm.define(box_name) do |c|
      c.vm.box = "ubuntu/#{box_name}"

      c.vm.provision :shell, inline: %(
        curl -s https://dist.crystal-lang.org/apt/setup.sh | bash
        apt-get install -y crystal git libgmp3-dev zlib1g-dev libedit-dev libxml2-dev libssl-dev libyaml-dev libreadline-dev g++
        curl -s https://crystal-lang.s3.amazonaws.com/llvm/llvm-3.5.0-1-linux-`uname -m`.tar.gz | tar xz -C /opt
        echo 'export LIBRARY_PATH="/opt/crystal/embedded/lib"' > /etc/profile.d/crystal.sh
        echo 'export PATH="$PATH:/opt/llvm-3.5.0-1/bin"' >> /etc/profile.d/crystal.sh
      )

      clone_crystal_from_vagrant.call(c)
    end
  end

  config.vm.define "freebsd11" do |c|
    c.ssh.shell = "csh"
    c.vm.box = "freebsd/FreeBSD-11.1-RELEASE"
    c.vm.guest = :freebsd
    c.vm.hostname = "freebsd11"

    c.vm.network "private_network", type: "dhcp"
    c.vm.synced_folder ".", "/vagrant", type: "nfs"

    # to build boehm-gc from git repository:
    #c.vm.provision :shell, inline: %(
    #  pkg install -y libtool automake autoconf libatomic_ops
    #)

    c.vm.provision :shell, inline: %(
      pkg install -qy git bash gmake pkgconf pcre libunwind clang35 libyaml gmp libevent boehm-gc-threaded
    )

    clone_crystal_from_vagrant.call(c)
  end

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 4096
    vb.cpus = 2
  end
end
