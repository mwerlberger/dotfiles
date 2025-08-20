{ pkgs
, username
, ...
}:
{
  # ============================================================================
  # Cloudflare Reverse Proxy Configuration using Caddy with ACME
  # ============================================================================
  # This configuration sets up Caddy as a reverse proxy with automatic SSL
  # certificates via Let's Encrypt using Cloudflare DNS challenge.
  #
  # TODO: Complete the following configuration steps:
  # 
  # 1. DOMAIN CONFIGURATION:
  #    - Replace "DOMAIN_NAME_HERE" with your actual domain (e.g., example.com)
  #    - Replace "SUBDOMAIN_HERE" with your desired subdomains
  #
  # 2. CLOUDFLARE SETUP:
  #    - Get a Cloudflare API token with Zone:Read and Zone:Zone permissions
  #    - Replace "YOUR_CLOUDFLARE_API_TOKEN_HERE" with your actual token
  #    - Consider using systemd credentials for production (see commented section)
  #
  # 3. EMAIL CONFIGURATION:
  #    - Replace "your-email@example.com" with your actual email
  #
  # 4. SERVICE CONFIGURATION:
  #    - Uncomment and configure the service blocks below
  #    - Adjust backend URLs and ports as needed
  #    - Add authentication where required
  #
  # 5. SECURITY:
  #    - Review and adjust security headers
  #    - Consider enabling basic auth for sensitive services
  #    - Test firewall rules and access controls
  # ============================================================================

  services.caddy = {
    enable = true;
    
    # TODO: Replace with your email address for Let's Encrypt notifications
    email = "web@werlberger.org";
    
    # Use Let's Encrypt production environment
    acmeCA = "https://acme-v02.api.letsencrypt.org/directory";
    
    # Main Caddy configuration with Cloudflare DNS challenge
    extraConfig = ''
      # Global configuration block
      {
        # Configure ACME to use Cloudflare DNS challenge
        # This allows certificates for internal services and wildcard domains
        acme_dns cloudflare {file.%C/cloudflare-api-token}
        # acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        
        # Optional: Enable admin API for debugging (remove in production)
        # admin localhost:2019
        
        # Global security headers that apply to all sites
        header {
          # Remove server information
          -Server
          
          # Security headers
          X-Content-Type-Options "nosniff"
          X-Frame-Options "SAMEORIGIN"
          X-XSS-Protection "1; mode=block"
          Referrer-Policy "strict-origin-when-cross-origin"
        }
      }
      
      # ========================================================================
      # Service Configurations - TODO: Uncomment and configure as needed
      # ========================================================================
      
      # Grafana Dashboard
      # TODO: Uncomment and replace DOMAIN_NAME_HERE with your domain
      grafana.werlberger.org {
        reverse_proxy localhost:3000 {
          header_up Host {host}
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
        }
        
        # Additional security headers for Grafana
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' ws: wss:;"
        }
      }
      
      # Prometheus Metrics (consider adding authentication)
      # TODO: Uncomment and replace DOMAIN_NAME_HERE with your domain
      # prometheus.werlberger.org {
      #   # Optional: Add basic authentication for security
      #   # basicauth {
      #   #   # TODO: Replace with actual username and bcrypt password hash
      #   #   # Generate hash with: caddy hash-password --plaintext yourpassword
      #   #   admin $2a$14$hashed_password_here
      #   # }
      #   
      #   reverse_proxy localhost:9090 {
      #     header_up Host {host}
      #     header_up X-Real-IP {remote_host}
      #     header_up X-Forwarded-For {remote_host}
      #     header_up X-Forwarded-Proto {scheme}
      #   }
      #   
      #   header {
      #     Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      #   }
      # }
      
      # TODO: Add additional services here using this template:
      # SERVICE_NAME.werlberger.org {
      #   # Optional authentication
      #   # basicauth {
      #   #   username $2a$14$hashed_password
      #   # }
      #   
      #   reverse_proxy localhost:PORT_NUMBER {
      #     header_up Host {host}
      #     header_up X-Real-IP {remote_host}
      #     header_up X-Forwarded-For {remote_host}
      #     header_up X-Forwarded-Proto {scheme}
      #   }
      #   
      #   header {
      #     Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      #   }
      # }
      
      # Default handler for undefined subdomains (optional)
      # *.werlberger.org {
      #   respond "Service not available" 404
      # }
      
      # Root domain redirect (optional)
      # DOMAIN_NAME_HERE {
      #   redir https://www.werlberger.org{uri} permanent
      # }
    '';
  };

  # Environment configuration for Caddy service
  # TODO: Replace with your actual Cloudflare API token
  # systemd.services.caddy.environment = {
  #   CLOUDFLARE_API_TOKEN = "1L56264Hx2COeWkdgF1SH2VUPE-ADaOSaqJKJT3s";
  # };

  # TODO: For production, use systemd credentials instead of environment variables
  # This is more secure as it keeps the token in a protected file
  # 
  # 1. Create a file with your token: echo "your_token_here" > /etc/caddy/cloudflare-token
  # 2. Set secure permissions: chmod 600 /etc/caddy/cloudflare-token
  # 3. Uncomment the following configuration:
  #
  systemd.services.caddy.serviceConfig = {
    LoadCredential = [ "cloudflare-api-token:/etc/caddy/cloudflare-token" ];
  };
  #
  # 4. Update the acme_dns line in extraConfig to:

  # Optional: Automatic certificate renewal check
  # Caddy handles this automatically, but you can add monitoring
  systemd.timers.caddy-cert-check = {
    enable = false;  # TODO: Set to true if you want periodic certificate monitoring
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

  systemd.services.caddy-cert-check = {
    enable = false;  # TODO: Set to true if you want periodic certificate monitoring
    description = "Check Caddy certificate status";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.caddy}/bin/caddy list-certificates";
      User = "caddy";
    };
  };
}