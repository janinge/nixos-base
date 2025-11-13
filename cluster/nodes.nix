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
  };

  hh4-nomad = {
    datacenter = "bgo-hh";
    hostId = "f2d31c54";
    diskLayout = "zfs-ssd";
    routedSubnet = "10.42.11.0/24";
    serviceIp = "10.42.11.1";
    serviceBridge = "cni-nomad0";
    publicIf = "enp1s0";
  };
}