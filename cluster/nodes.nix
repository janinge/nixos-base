{
  edge-gw = {
    datacenter = "osl-hh";
    hostId = "13f00fb0";
    diskLayout = "ext4-vm";
    routedSubnet = "10.42.1.0/24";
    serviceIp = "10.42.1.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp1s0";
    kernelModules = [ "kvm-intel" ];
    isRegistry = true;
    isGateway = true;
    patroni = true;
  };

  aws-gw = {
    datacenter = "sto-aw";
    hostId = "9c2b4d1a";
    diskLayout = "ext4-ebs";
    routedSubnet = "10.42.20.0/24";
    serviceIp = "10.42.20.1";
    serviceBridge = "cni-nomad0";
    publicIf = "ens5";

    system = "aarch64-linux";
    nixpkgs.hostPlatform = "aarch64-linux";
  };

  cb-weed = {
    datacenter = "fra-cb";
    hostId = "1f4f0019";
    diskLayout = "ext4-vm";
    rootDevice = "/dev/sda";
    routedSubnet = "10.42.21.0/24";
    serviceIp = "10.42.21.1";
    serviceBridge = "cni-nomad0";
    publicIf = "ens18";
    kernelModules = [ "kvm-intel" ];
    garage = {
      enable = true;
      capacity = "800G";
      nodeId = "a8a8bbc6536dbffa98871c74413a26079f83397a55dc1761481e21c440248e8f";
    };
  };

  lw-gw = {
    datacenter = "ams-lw";
    hostId = "866330b1";
    diskLayout = "ext4-vm";
    routedSubnet = "10.42.22.0/24";
    serviceIp = "10.42.22.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp1s0";
    kernelModules = [ "kvm-intel" ];
  };

  sto-s2-01 = {
    datacenter = "sto-hh";
    hostId = "f0e80462";
    diskLayout = "ext4-vm-zfs-data";
    rootDevice = "/dev/vda";
    dataDevice = "/dev/vdb";
    routedSubnet = "10.42.23.0/24";
    serviceIp = "10.42.23.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp1s0";
    garage = {
      enable = true;
      capacity = "2560G";
      nodeId = "e9c566745ca3b22739f6b356d6664a2ed6870eb80b77338bd74d9608eca79a7a";
    };
  };

  ams-c1-01 = {
    datacenter = "ams-lw";
    hostId = "217942d2";
    diskLayout = "ext4-luks-vm";
    rootDevice = "/dev/sda";
    routedSubnet = "10.42.24.0/24";
    serviceIp = "10.42.24.1";
    serviceBridge = "cni-nomad0";
    publicIf = "ens3";
    kernelModules = [];
    isRegistry = true;
    isGateway = true;
    patroni = true;
  };

  ams-c1-02 = {
    datacenter = "ams-do";
    hostId = "b8a17c4e";
    diskLayout = "ext4-luks-vm";
    rootDevice = "/dev/vda";
    routedSubnet = "10.42.26.0/24";
    serviceIp = "10.42.26.1";
    serviceBridge = "cni-nomad0";
    publicIf = "eth0";
    kernelModules = [];
  };

  ams-c2-02 = {
    datacenter = "ams-do";
    hostId = "c9b28d5f";
    diskLayout = "ext4-luks-vm";
    rootDevice = "/dev/vda";
    routedSubnet = "10.42.27.0/24";
    serviceIp = "10.42.27.1";
    serviceBridge = "cni-nomad0";
    publicIf = "eth0";
    kernelModules = [];
  };

  fbv-c2-01 = {
    datacenter = "bgo-fb";
    hostId = "155e3659";
    diskLayout = "ext4-vm";
    rootDevice = "/dev/sda";
    routedSubnet = "10.42.10.0/24";
    serviceIp = "10.42.10.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp0s5";
    kernelModules = [ "kvm-intel" ];
    garage = {
      enable = true;
      capacity = "160G";
      nodeId = "07d495a05f058241073783a50396c080bbef991966fb9a8a02f8194cf4c61e1b";
    };
  };

  fra-c2-01 = {
    datacenter = "fra-c2";
    hostId = "d9f3a15c";
    diskLayout = "ext4-luks-vm";
    rootDevice = "/dev/sda";
    kernelModules = [ "kvm-intel" ];
    routedSubnet = "10.42.25.0/24";
    serviceIp = "10.42.25.1";
    serviceBridge = "cni-nomad0";
    publicIf = "ens18";
    isGateway = true;
  };

  hh4-nomad = {
    datacenter = "bgo-hh";
    hostId = "f2d31c54";
    diskLayout = "zfs-ssd";
    routedSubnet = "10.42.11.0/24";
    serviceIp = "10.42.11.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp1s0";
    isRegistry = true;
    garage = {
      enable = true;
      capacity = "1024G";
      nodeId = "3464e2c9dd0b19075d04f4e4775441419f4a4865d3d2db95d9cdaed56cdac93e";
    };
  };
}
