# Nomad host volumes shared across all clients.
# Per-host volumes can be added alongside these in each host file.
{
  "local-stalwart" = {
    path = "/var/lib/nomad-volumes/stalwart";
    readOnly = false;
    createDir = true;
  };
  "weed-p2p" = {
    path = "/mnt/seaweedfs/p2p";
    readOnly = false;
    createDir = false;
  };
  "local-p2p" = {
    path = "/var/lib/nomad-volumes/p2p";
    readOnly = false;
    createDir = true;
  };
}