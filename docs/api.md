# API 文档

## 基础信息
- Base URL（默认）：`http://<SERVER_IP>:18080`
- API 前缀：`/sub`

> 如果你使用了反向代理或域名，请替换为你的实际地址。

## 认证方式

### 1) 订阅用户会话（登录后）
- Header：`Authorization: Bearer <session_token>`
- 或：`X-Session-Token: <session_token>`

### 2) 管理员 API Key（/sub/admin/*）
- Header：`X-Sub-Admin-Key: <SUB_ADMIN_API_KEY>`
- 也支持：`X-API-Key` 或 `Authorization: Bearer <key>`

## 用户认证与自助接口

### 登录
`POST /sub/auth/login`

请求体：
```json
{
  "username": "alice",
  "password": "your-password"
}
```

响应：
```json
{
  "success": true,
  "token": "<session_token>",
  "user": {
    "id": "...",
    "username": "alice",
    "name": "Alice",
    "role": "user"
  }
}
```

### 验证会话
`GET /sub/auth/verify`

响应：
```json
{ "success": true, "user": { "id": "...", "username": "alice", "role": "user" } }
```

### 退出登录
`POST /sub/auth/logout`

响应：
```json
{ "success": true }
```

### 修改密码
`POST /sub/auth/change-password`

请求体：
```json
{ "oldPassword": "old", "newPassword": "newpass" }
```

### 获取订阅信息
`GET /sub/auth/subscription`

响应（示例）：
```json
{
  "success": true,
  "data": {
    "user": { "username": "alice", "name": "Alice", "role": "user" },
    "subscriptionUrl": "http://<host>:18080/sub/<token>",
    "tokenStatus": {
      "oneTimeUse": true,
      "isConsumed": false,
      "accessCount": 3,
      "expiresAt": "2026-12-31T23:59:59.000Z"
    },
    "nodes": [
      { "id": "hysteria2", "name": "Hysteria2-Node", "type": "hysteria2" }
    ]
  }
}
```

### 重新生成订阅链接
`POST /sub/auth/regenerate-token`

响应：
```json
{
  "success": true,
  "data": {
    "subscriptionUrl": "http://<host>:18080/sub/<new-token>",
    "token": "<new-token>"
  },
  "message": "订阅链接已重新生成"
}
```

### 获取节点详情
`GET /sub/auth/nodes`

响应：
```json
{
  "success": true,
  "data": [
    { "id": "hysteria2", "name": "Hysteria2-Node", "type": "hysteria2", "url": "..." }
  ]
}
```

### 获取用户统计
`GET /sub/auth/stats`

### 获取用户流量
`GET /sub/auth/user-traffic`

### 获取系统概览
`GET /sub/auth/overview`

### 获取流量统计
`GET /sub/auth/traffic`

## 订阅管理员（用户会话）
> 需要订阅用户角色为 `admin` 且无 `parentId`。

### 管理员统计
`GET /sub/auth/admin-stats`

### 下级用户列表
`GET /sub/auth/sub-users`

### 创建下级用户
`POST /sub/auth/sub-users`

请求体：
```json
{
  "username": "bob",
  "password": "pass1234",
  "name": "Bob",
  "expiresAt": "2026-12-31T23:59:59.000Z",
  "oneTimeUse": true
}
```

### 更新下级用户
`PUT /sub/auth/sub-users/:userId`

请求体（可选字段）：
```json
{
  "name": "Bob",
  "expiresAt": "2026-12-31T23:59:59.000Z",
  "isActive": true,
  "trafficLimit": 107374182400
}
```

### 重置下级用户密码
`POST /sub/auth/sub-users/:userId/reset-password`

### 重新生成下级用户订阅链接
`POST /sub/auth/sub-users/:userId/regenerate-token`

### 重置下级用户流量
`POST /sub/auth/sub-users/:userId/reset-traffic`

### 删除下级用户
`DELETE /sub/auth/sub-users/:userId`

## 订阅内容

### 获取订阅内容
`GET /sub/:token`

- 返回 `text/plain`
- 响应头包含 `Subscription-Userinfo`
- 订阅链接可以带查询参数（如 `?format=clash`），当前版本返回内容一致

## 管理员 API（API Key）

### 用户列表
`GET /sub/admin/users`

### 创建用户
`POST /sub/admin/users`

请求体（示例）：
```json
{
  "username": "alice",
  "password": "pass1234",
  "name": "Alice",
  "role": "admin",
  "expiresAt": "2026-12-31T23:59:59.000Z",
  "oneTimeUse": false
}
```

### 更新用户
`PUT /sub/admin/users/:userId`

### 设置用户角色
`PUT /sub/admin/users/:userId/role`

请求体：
```json
{ "role": "admin" }
```

### 重新生成用户订阅链接
`POST /sub/admin/users/:userId/regenerate-token`

### 重置用户密码
`POST /sub/admin/users/:userId/reset-password`

### 删除用户
`DELETE /sub/admin/users/:userId`

### Token 列表
`GET /sub/admin/tokens`

### 创建 Token
`POST /sub/admin/tokens`

请求体（示例）：
```json
{
  "name": "marketing",
  "expiryDays": 30,
  "maxAccess": 0,
  "oneTimeUse": false,
  "allowedIPs": [],
  "enabledNodes": [],
  "userId": null
}
```

### 删除 Token
`DELETE /sub/admin/tokens/:token`

### 节点列表
`GET /sub/admin/nodes`

## Hysteria2 认证相关

### Hysteria2 HTTP 认证（内置路由）
`POST /sub/auth/hysteria`

> 供 Hysteria2 服务调用，用于校验订阅 Token。

请求体（示例）：
```json
{ "addr": "1.2.3.4:54321", "auth": "<token>", "tx": 0 }
```

响应：
```json
{ "ok": true, "id": "<userId>" }
```

### Hysteria2 Auth 服务（独立端口）
- 监听：`HY2_AUTH_PORT`（默认 `9998`）
- 路径：`POST /auth`

> 这是独立进程服务，不在 `/sub` 前缀下。

