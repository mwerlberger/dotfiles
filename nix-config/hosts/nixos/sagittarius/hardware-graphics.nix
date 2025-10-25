{ pkgs, ... }:

{
  # Enable hardware acceleration for Intel Quick Sync Video
  # This is used by Jellyfin for hardware-accelerated transcoding
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver  # VAAPI driver for modern Intel GPUs (>= Broadwell)
      intel-compute-runtime # OpenCL support for Intel GPUs
      vaapiVdpau
      libvdpau-va-gl
      onevpl-intel-gpu    # oneVPL runtime for Intel QSV (Quick Sync Video)
    ];
  };

  # Load i915 kernel module for Intel integrated graphics
  boot.initrd.kernelModules = [ "i915" ];
}
