# Nomad host volumes shared across all clients.
# Per-host volumes can be added alongside these in each host file.
{
  "seaweedfs" = {
    path = "/mnt/seaweedfs";
    readOnly = false;
    createDir = false;
  };
  "local-stalwart" = {
    path = "/var/lib/nomad-volumes/stalwart";
    readOnly = false;
    createDir = true;
  };
  "local-p2p" = {
    path = "/var/lib/nomad-volumes/p2p";
    readOnly = false;
    createDir = true;
  };
}