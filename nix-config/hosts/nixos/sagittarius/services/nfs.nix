{ ... }:
{
  services.nfs.server = {
    enable = true;
    # fsid=0 makes /data/lake the NFSv4 pseudo-root.
    # Clients mount nas-ip:/ and get /data/lake.
    # Allowed sources: LAN (192.168.1.0/24) and Tailscale CGNAT (100.64.0.0/10).
    exports = ''
      /data/lake           192.168.1.0/24(ro,sync,fsid=0,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.64.0.0/10(ro,sync,fsid=0,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
      /data/lake/backups   192.168.1.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.64.0.0/10(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
      /data/lake/documents 192.168.1.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.64.0.0/10(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
      /data/lake/media     192.168.1.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.64.0.0/10(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
      /data/lake/photos    192.168.1.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000) 100.64.0.0/10(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
    '';
  };

  # NFSv4 only — disable v2/v3.
  services.nfs.settings = {
    nfsd = {
      vers2 = "n";
      vers3 = "n";
      vers4 = "y";
      "vers4.1" = "y";
      "vers4.2" = "y";
    };
  };

  # idmapd translates user@domain strings <-> local uids.
  # All clients (macOS, other machines) must use the same domain string.
  services.nfs.idmapd.settings = {
    General.Domain = "sagittarius.s63";
  };

  # NFSv4 only needs TCP 2049. tailscale0 is already a trusted firewall
  # interface, so this rule only matters for LAN clients.
  networking.firewall.allowedTCPPorts = [ 2049 ];
}
