{
  edge-gw = {
    datacenter = "osl-hh";
    diskLayout = "zfs-ssd";
    routedSubnet = "10.42.1.0/24";
  };

  hh4-nomad = {
    datacenter = "bgo-hh";
    diskLayout = "ext4-vm";
    routedSubnet = "10.42.2.0/24";
  };
}