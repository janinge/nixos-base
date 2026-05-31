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
    datacenter = "ams-lw";
    hostId = "b8a17c4e";
    diskLayout = "ext4-luks-vm";
    rootDevice = "/dev/vda";
    routedSubnet = "10.42.26.0/24";
    serviceIp = "10.42.26.1";
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
  };
}
