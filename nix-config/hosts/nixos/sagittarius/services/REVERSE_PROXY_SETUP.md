# Cloudflare Reverse Proxy Setup Guide

This configuration sets up Caddy as a reverse proxy with automatic SSL certificates through Let's Encrypt using Cloudflare's DNS challenge. This allows you to securely expose your internal services through your domain with automatic HTTPS.

## 🚀 Quick Start

1. **Configure your domain and Cloudflare API token**
2. **Update the service configurations**
3. **Deploy the configuration**
4. **Test your setup**

## 📋 Configuration Steps

### Step 1: Cloudflare Setup

1. **Get your API Token:**
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
   - Click "Create Token"
   - Use the "Custom token" option with these permissions:
     - **Zone:Zone:Read** (for all zones or specific zone)
     - **Zone:DNS:Edit** (for all zones or specific zone)
   - Copy the generated token

2. **Update DNS records in Cloudflare:**
   - Add A records pointing your subdomains to your server's public IP
   - Example: `grafana.yourdomain.com` → `YOUR_SERVER_IP`

### Step 2: Update Configuration Files

#### In `reverse-proxy.nix`:

1. **Set your email address:**
   ```nix
   email = "your-actual-email@example.com";
   ```

2. **Set your Cloudflare API token:**
   ```nix
   systemd.services.caddy.environment = {
     CLOUDFLARE_API_TOKEN = "your_actual_cloudflare_api_token_here";
   };
   ```

3. **Configure your services:**
   Uncomment and modify the service blocks:
   ```nix
   # Change this:
   # grafana.DOMAIN_NAME_HERE {
   
   # To this:
   grafana.yourdomain.com {
   ```

### Step 3: Example Service Configurations

#### Grafana (Port 3000):
```nix
grafana.yourdomain.com {
  reverse_proxy localhost:3000 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
  
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' ws: wss:;"
  }
}
```

#### Prometheus (Port 9090) with Basic Auth:
```nix
prometheus.yourdomain.com {
  basicauth {
    admin $2a$14$your_bcrypt_hashed_password_here
  }
  
  reverse_proxy localhost:9090 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
  
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
  }
}
```

### Step 4: Security Best Practices

#### Generate Password Hashes for Basic Auth:
```bash
# On your NixOS system after deployment:
caddy hash-password --plaintext yourpassword
```

#### Use Systemd Credentials (Recommended for Production):
1. Create a secure token file:
   ```bash
   sudo mkdir -p /etc/caddy
   echo "your_cloudflare_api_token" | sudo tee /etc/caddy/cloudflare-token
   sudo chmod 600 /etc/caddy/cloudflare-token
   sudo chown caddy:caddy /etc/caddy/cloudflare-token
   ```

2. Update the configuration to use credentials:
   ```nix
   systemd.services.caddy.serviceConfig = {
     LoadCredential = [ "cloudflare-api-token:/etc/caddy/cloudflare-token" ];
   };
   ```

3. Update the acme_dns line:
   ```
   acme_dns cloudflare {file.%C/cloudflare-api-token}
   ```

### Step 5: Deployment

1. **Build and test the configuration:**
   ```bash
   sudo nixos-rebuild test --flake .#sagittarius
   ```

2. **If everything works, apply permanently:**
   ```bash
   sudo nixos-rebuild switch --flake .#sagittarius
   ```

3. **Check Caddy status:**
   ```bash
   sudo systemctl status caddy
   sudo journalctl -u caddy -f
   ```

### Step 6: Verification

1. **Check certificate status:**
   ```bash
   sudo caddy list-certificates
   ```

2. **Test your services:**
   - Visit `https://grafana.yourdomain.com`
   - Visit `https://prometheus.yourdomain.com`

3. **Verify HTTPS:**
   ```bash
   curl -I https://grafana.yourdomain.com
   ```

## 🔧 Troubleshooting

### Common Issues:

1. **Certificate generation fails:**
   - Verify your Cloudflare API token has correct permissions
   - Check DNS propagation: `dig grafana.yourdomain.com`
   - Review Caddy logs: `sudo journalctl -u caddy -f`

2. **Service not accessible:**
   - Verify firewall ports 80 and 443 are open
   - Check that backend services are running on expected ports
   - Verify DNS records point to your server

3. **Permission denied:**
   - Ensure Caddy service has proper permissions
   - Check file ownership for credential files

### Useful Commands:

```bash
# Check Caddy configuration
sudo caddy validate --config /etc/caddy/Caddyfile

# Reload configuration without restart
sudo caddy reload --config /etc/caddy/Caddyfile

# View Caddy admin API (if enabled)
curl http://localhost:2019/config/

# Test DNS resolution
nslookup grafana.yourdomain.com
```

## 📚 Additional Resources

- [Caddy Documentation](https://caddyserver.com/docs/)
- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [NixOS Caddy Options](https://search.nixos.org/options?query=services.caddy)

## 🔐 Security Considerations

1. **Use strong passwords** for basic authentication
2. **Regularly rotate** your Cloudflare API token
3. **Monitor access logs** for suspicious activity
4. **Keep Caddy updated** through NixOS updates
5. **Use fail2ban** or similar tools for additional protection
6. **Consider VPN access** for administrative interfaces

## 🎯 Next Steps

After completing the basic setup, consider:

1. **Adding more services** using the provided templates
2. **Setting up monitoring** for certificate expiration
3. **Configuring backup** for your Caddy configuration
4. **Implementing log aggregation** for better monitoring
5. **Adding rate limiting** for public-facing services