This directory contains age-encrypted secrets used by agenix.

Files:
- cloudflare-api-token.age — an env file encrypted with age, containing a single line:

  CLOUDFLARE_API_TOKEN=...your token...

How to (re)create:
1) Ensure your local age identity matches the host decryption identity. In this repo we use the host's SSH key (/etc/ssh/ssh_host_ed25519_key) for decryption on the machine, so add your dev key for editing:

   - Get recipients (public keys):
     - Host: `ssh-ed25519` public key from /etc/ssh/ssh_host_ed25519_key.pub on sagittarius
     - Your dev key: `age-keygen -y ~/.config/age/key.txt` or use your SSH pub key with `ssh-to-age`.

2) Install agenix CLI locally:
   nix profile install nixpkgs#agenix

3) Create or edit the plaintext env file and encrypt it:
   echo 'CLOUDFLARE_API_TOKEN=...'
     | age -r <HOST_AGE_PUB_OR_SSH_TO_AGE> -r <YOUR_AGE_PUB> -o secrets/cloudflare-api-token.age

Alternatively, use `agenix -e secrets/cloudflare-api-token.age` and let it pick recipients from an age.secrets file.

Note: The NixOS config reads this file into Caddy via systemd EnvironmentFile, so keep the format KEY=VALUE.
