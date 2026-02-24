{
  edge-gw = {
    datacenter = "osl-hh";
    hostId = "13f00fb0";
    diskLayout = "ext4-vm";
    routedSubnet = "10.42.1.0/24";
    serviceIp = "10.42.1.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp1s0";
    isRegistry = true;
    isGateway = true;
    weedMaster = true;
    weedFiler = true;
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
    isRegistry = true;
    isGateway = true;
    weedMaster = true;
    patroni = true;
  };

  lw-gw = {
    datacenter = "ams-lw";
    hostId = "866330b1";
    diskLayout = "ext4-vm";
    routedSubnet = "10.42.22.0/24";
    serviceIp = "10.42.22.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp1s0";
  };

  fbv-c2-01 = {
    datacenter = "bgo-fb";
    hostId = "155e3659";
    diskLayout = "ext4-vm";
    routedSubnet = "10.42.10.0/24";
    serviceIp = "10.42.10.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp0s5";
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
    weedMaster = true;
    patroni = true;
  };
}