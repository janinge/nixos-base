# Nomad host volumes shared across all clients.
# Per-host volumes can be added alongside these in each host file.
{
  "local-stalwart" = {
    path = "/var/lib/nomad-volumes/stalwart";
    readOnly = false;
    createDir = true;
  };
}
