# Hysteria2 稳定性守护

`install-hy2-guardian.sh` 为已有 Hysteria2 节点增加四层保护，不改变用户、
订阅 Token 或节点协议：

1. systemd 在进程异常退出后自动拉起；
2. 每五分钟检查进程、UDP 端口、证书/私钥、鉴权、订阅公网路由、DNS 和
   IPv4 出口，只在本地进程/端口异常时重启 HY2；
3. 单独续期 HY2 使用的证书，避免其他 Certbot 证书失败阻断这条续期链；
4. HY2 运行配置使用 DoH，避开 VPS 上不稳定的明文 UDP DNS。

生产安装示例：

```bash
sudo bash scripts/install-hy2-guardian.sh \
  --domain nodehome.example.com \
  --expected-ip 203.0.113.10 \
  --public-health-url https://nodehome.example.com/sub/health
```

安装后检查：

```bash
systemctl status hysteria-server.service
systemctl list-timers hy2-healthcheck.timer hy2-certificate-renew.timer
sudo /usr/local/sbin/hy2-healthcheck
sudo /usr/local/sbin/hy2-cert-renew --dry-run
```

证书 `--dry-run` 会执行真实 deploy hook，因此会安全重启一次 HY2，这是续期演练的一部分。

升级 Hysteria 二进制时可使用带官方校验和与失败回滚的脚本：

```bash
sudo bash scripts/upgrade-hysteria.sh --version 2.10.0
```

健康检查失败会进入 systemd journal：

```bash
journalctl -u hy2-healthcheck.service --since today
```

`HY2_HEALTH status=failed` 前的 `FAIL` 行会区分本地守护进程、TLS、DNS、鉴权、
公网订阅路由和出口故障。DNS/鉴权/公网失败不会盲目重启 HY2，避免把外部依赖
抖动放大成服务中断。
