{ lib, ... }:

{
  # NFSv4 client domain must match the server's idmapd domain
  environment.etc."nfs.conf" = {
    text = ''
      nfs.client.default_nfs4domain = sagittarius.s63
    '';
  };

  # Automount map — each ZFS dataset mounted directly (avoids crossmnt issues)
  # Mounts on demand under /Volumes/nas/<name>
  environment.etc."auto_nfs" = {
    text = ''
      photos    -fstype=nfs,vers=4,resvport,soft,intr,retrans=2,timeo=5  sagittarius:/photos
      backups   -fstype=nfs,vers=4,resvport,soft,intr,retrans=2,timeo=5  sagittarius:/backups
      documents -fstype=nfs,vers=4,resvport,soft,intr,retrans=2,timeo=5  sagittarius:/documents
      media     -fstype=nfs,vers=4,resvport,soft,intr,retrans=2,timeo=5  sagittarius:/media
    '';
  };

  # Register the automount map — replicates macOS Sequoia defaults plus our entry
  environment.etc."auto_master" = {
    text = ''
      #
      # Automounter master map
      #
      +auto_master            # Use directory service
      /net                    -hosts    -nobrowse,hidefromfinder,nosuid
      /home                   auto_home -nobrowse,hidefromfinder
      /Network/Servers        -fstab
      /-                      -static
      /Volumes/nas            auto_nfs  -nosuid,nodev
    '';
  };

  # Reload autofs after activation so changes take effect without reboot
  system.activationScripts.postActivation.text = lib.mkAfter ''
    /usr/sbin/automount -vc 2>/dev/null || true
  '';

  # Disable Spotlight indexing on the NAS mount (idempotent)
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    /usr/bin/mdutil -i off /Volumes/nas 2>/dev/null || true
  '';
}
