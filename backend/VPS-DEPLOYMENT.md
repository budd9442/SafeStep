# SafeStep Backend - VPS Deployment Guide

This guide helps you deploy the SafeStep backend on a VPS with existing nginx.

## Prerequisites

- VPS with Ubuntu/Debian
- Docker and Docker Compose installed
- Existing nginx installation
- Domain name (optional but recommended)

## Step 1: Clone and Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd backend

# Copy environment file
cp env.example .env

# Edit environment variables
nano .env
```

## Step 2: Configure Environment Variables

Edit `.env` file with your production settings:

```env
# Server Configuration
PORT=3000
NODE_ENV=production

# Database Configuration
DATABASE_URL=postgresql://safestep:safestep123@postgres:5432/safestep_db

# JWT Configuration
JWT_SECRET=your_very_secure_jwt_secret_here
JWT_EXPIRES_IN=7d

# mSpace Configuration
MSPACE_BASE_URL=https://api.mspace.lk
MSPACE_APPLICATION_ID=APP_008956
MSPACE_PASSWORD=bab3f431230a12998b0b72296642a5f6
MSPACE_VERSION=2.0
MSPACE_APPLICATION_HASH=safestep_hash
```

## Step 3: Deploy with Docker Compose

```bash
# Build and start services
docker-compose up -d

# Check if services are running
docker-compose ps

# View logs
docker-compose logs -f app
```

## Step 4: Configure Existing Nginx

### Option A: Add to existing nginx config

1. **Edit your nginx configuration:**
   ```bash
   sudo nano /etc/nginx/sites-available/default
   ```

2. **Add the SafeStep configuration:**
   ```nginx
   # Add this to your existing server block
   upstream safestep_api {
       server 127.0.0.1:3000;
   }

   # Rate limiting zone
   limit_req_zone $binary_remote_addr zone=safestep_api:10m rate=10r/s;

   server {
       listen 80;
       server_name your-domain.com; # Replace with your domain

       # Your existing locations...

       # SafeStep API routes
       location /api/ {
           limit_req zone=safestep_api burst=20 nodelay;
           
           proxy_pass http://safestep_api;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection 'upgrade';
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_cache_bypass $http_upgrade;
           
           # Timeouts
           proxy_connect_timeout 60s;
           proxy_send_timeout 60s;
           proxy_read_timeout 60s;
       }

       # Health check
       location /health {
           proxy_pass http://safestep_api/api/health;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

3. **Test and reload nginx:**
   ```bash
   sudo nginx -t
   sudo systemctl reload nginx
   ```

### Option B: Use the provided config file

1. **Copy the configuration:**
   ```bash
   sudo cp nginx-vps-config.conf /etc/nginx/sites-available/safestep
   ```

2. **Edit the configuration:**
   ```bash
   sudo nano /etc/nginx/sites-available/safestep
   ```
   - Replace `your-domain.com` with your actual domain
   - Uncomment HTTPS section if you have SSL certificates

3. **Enable the site:**
   ```bash
   sudo ln -s /etc/nginx/sites-available/safestep /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl reload nginx
   ```

## Step 5: SSL Configuration (Optional)

If you have SSL certificates:

1. **Update the nginx configuration:**
   ```nginx
   server {
       listen 443 ssl http2;
       server_name your-domain.com;

       ssl_certificate /path/to/your/cert.pem;
       ssl_certificate_key /path/to/your/key.pem;

       # SSL configuration
       ssl_protocols TLSv1.2 TLSv1.3;
       ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
       ssl_prefer_server_ciphers off;

       # Same location blocks as HTTP
       location /api/ {
           limit_req zone=safestep_api burst=20 nodelay;
           proxy_pass http://safestep_api;
           # ... same proxy settings
       }
   }
   ```

2. **Redirect HTTP to HTTPS:**
   ```nginx
   server {
       listen 80;
       server_name your-domain.com;
       return 301 https://$server_name$request_uri;
   }
   ```

## Step 6: Firewall Configuration

```bash
# Allow HTTP and HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Allow SSH (if not already allowed)
sudo ufw allow ssh

# Enable firewall
sudo ufw enable
```

## Step 7: Test the Deployment

```bash
# Test the API
curl http://your-domain.com/api/health

# Test OTP request
curl -X POST http://your-domain.com/api/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber": "+94716177301"}'
```

## Step 8: Monitoring and Maintenance

### View logs:
```bash
# Application logs
docker-compose logs -f app

# Database logs
docker-compose logs -f postgres

# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Update the application:
```bash
# Pull latest changes
git pull

# Rebuild and restart
docker-compose down
docker-compose up -d --build
```

### Backup database:
```bash
# Create backup
docker-compose exec postgres pg_dump -U safestep safestep_db > backup.sql

# Restore backup
docker-compose exec -T postgres psql -U safestep safestep_db < backup.sql
```

## Troubleshooting

### Common Issues:

1. **Port 3000 already in use:**
   ```bash
   # Check what's using port 3000
   sudo netstat -tlnp | grep :3000
   
   # Kill the process or change port in docker-compose.yml
   ```

2. **Database connection issues:**
   ```bash
   # Check if postgres is running
   docker-compose ps postgres
   
   # Check database logs
   docker-compose logs postgres
   ```

3. **Nginx configuration errors:**
   ```bash
   # Test nginx configuration
   sudo nginx -t
   
   # Check nginx error logs
   sudo tail -f /var/log/nginx/error.log
   ```

4. **Permission issues:**
   ```bash
   # Fix file permissions
   sudo chown -R $USER:$USER .
   sudo chmod -R 755 .
   ```

## Security Considerations

1. **Change default passwords** in `.env`
2. **Use strong JWT secret**
3. **Configure SSL certificates**
4. **Set up firewall rules**
5. **Regular security updates**
6. **Monitor logs for suspicious activity**

## Performance Optimization

1. **Enable nginx caching** for static assets
2. **Configure database connection pooling**
3. **Set up Redis for caching** (optional)
4. **Monitor resource usage**
5. **Scale horizontally** if needed

Your SafeStep backend is now deployed and ready to use! 