{
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "schedutil";
  };

  boot.kernelParams = [
    "intel_pstate=passive"
    "intel_idle.max_cstate=9"
    "pcie_aspm=force"
    "ahci.mobile_lpm_policy=3"
  ];
}