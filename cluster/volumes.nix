# Nomad host volumes shared across all clients.
# Per-host volumes can be added alongside these in each host file.
{
  "local-stalwart" = {
    path = "/var/lib/nomad-volumes/stalwart";
    readOnly = false;
    createDir = true;
  };
  # These local placeholders let Nomad start before the SeaweedFS mount exists.
  # Jobs using them must constrain on ${meta.storage_weed} == "ready"; otherwise
  # they can land on the placeholder directories and write locally, which is unsupported.
  "weed-authentik" = {
    path = "/mnt/seaweedfs/authentik";
    readOnly = false;
    createDir = true;
  };
  "weed-music" = {
    path = "/mnt/seaweedfs/music";
    readOnly = false;
    createDir = true;
  };
  "weed-p2p" = {
    path = "/mnt/seaweedfs/p2p";
    readOnly = false;
    createDir = true;
  };
}
