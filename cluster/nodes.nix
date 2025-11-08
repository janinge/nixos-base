{
  edge-gw = {
    datacenter = "osl-hh";
    hostId = "13f00fb0";
    diskLayout = "ext4-vm";
    routedSubnet = "10.42.1.0/24";
  };

  hh4-nomad = {
    datacenter = "bgo-hh";
    hostId = "f2d31c54";
    diskLayout = "zfs-ssd";
    routedSubnet = "10.42.11.0/24";
  };
}