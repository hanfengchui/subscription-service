# 安全建议

- `SUB_ADMIN_API_KEY` 属于高敏感信息，请妥善保管。
- 不要对公网暴露 MySQL/Redis 端口。
- 建议用防火墙只开放 Nginx 端口。
- 如果使用 HTTPS 终端，请设置 `SUB_PUBLIC_BASE_URL` 为 HTTPS 地址。
- 建议定期轮换密钥与密码，并重启服务。
