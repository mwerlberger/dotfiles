{ pkgs, ... }:

{
  # Enable hardware acceleration for Intel Quick Sync Video
  # This is used by Jellyfin for hardware-accelerated transcoding
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver  # VAAPI driver for modern Intel GPUs (>= Broadwell)
      intel-compute-runtime # OpenCL support for Intel GPUs
      libva-vdpau-driver
      libvdpau-va-gl
      vpl-gpu-rt
    ];
  };

  # Load i915 kernel module for Intel integrated graphics
  boot.initrd.kernelModules = [ "i915" ];
}
