# Security Notes

- Keep `SUB_ADMIN_API_KEY` private. Treat it like a password.
- Do not expose MySQL/Redis ports to the public internet.
- Use a firewall to allow only the Nginx port.
- If you terminate TLS outside Docker, set `SUB_PUBLIC_BASE_URL` to the HTTPS URL.
- Rotate keys periodically and restart the stack after changes.
