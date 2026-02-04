<template>
  <div
    class="min-h-screen bg-gradient-to-br from-gray-50 via-blue-50/30 to-purple-50/20 dark:from-gray-900 dark:via-gray-900 dark:to-gray-800"
  >
    <!-- 导航栏 -->
    <nav
      class="sticky top-0 z-50 border-b border-gray-200/50 bg-white/80 shadow-sm backdrop-blur-xl dark:border-gray-700/50 dark:bg-gray-800/80"
    >
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="flex h-16 justify-between">
          <div class="flex items-center">
            <div class="flex flex-shrink-0 items-center">
              <div
                class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-blue-500 to-purple-600 shadow-lg shadow-blue-500/25"
              >
                <svg
                  class="h-6 w-6 text-white"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                  />
                </svg>
              </div>
              <span
                class="ml-3 bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-xl font-bold text-transparent dark:from-blue-400 dark:to-purple-400"
                >机场订阅</span
              >
            </div>
            <div class="ml-6 hidden sm:ml-10 sm:block">
              <div class="flex items-baseline space-x-1 sm:space-x-2">
                <button :class="tabClass('subscription')" @click="activeTab = 'subscription'">
                  <i class="fas fa-link mr-1.5"></i>我的订阅
                </button>
                <button
                  v-if="subStore.isAdmin"
                  :class="tabClass('users')"
                  @click="activeTab = 'users'"
                >
                  <i class="fas fa-users mr-1.5"></i>用户管理
                </button>
                <button :class="tabClass('tutorial')" @click="activeTab = 'tutorial'">
                  <i class="fas fa-book mr-1.5"></i>使用教程
                </button>
                <button :class="tabClass('settings')" @click="activeTab = 'settings'">
                  <i class="fas fa-cog mr-1.5"></i>设置
                </button>
              </div>
            </div>
          </div>
          <div class="flex items-center space-x-2 sm:space-x-4">
            <div class="hidden text-sm text-gray-700 dark:text-gray-300 sm:block">
              欢迎, <span class="font-medium">{{ subStore.userName }}</span>
              <span
                v-if="subStore.isAdmin"
                class="ml-1 rounded-full bg-gradient-to-r from-blue-500 to-purple-500 px-2 py-0.5 text-xs text-white"
                >管理员</span
              >
            </div>
            <ThemeToggle mode="compact" />
            <button
              class="rounded-lg px-3 py-2 text-sm font-medium text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-300"
              @click="handleLogout"
            >
              <i class="fas fa-sign-out-alt"></i>
              <span class="ml-1.5 hidden sm:inline">退出</span>
            </button>
          </div>
        </div>
        <!-- 移动端标签栏 -->
        <div class="flex space-x-1 overflow-x-auto pb-3 sm:hidden">
          <button :class="tabClassMobile('subscription')" @click="activeTab = 'subscription'">
            <i class="fas fa-link"></i>
            <span>订阅</span>
          </button>
          <button
            v-if="subStore.isAdmin"
            :class="tabClassMobile('users')"
            @click="activeTab = 'users'"
          >
            <i class="fas fa-users"></i>
            <span>用户</span>
          </button>
          <button :class="tabClassMobile('tutorial')" @click="activeTab = 'tutorial'">
            <i class="fas fa-book"></i>
            <span>教程</span>
          </button>
          <button :class="tabClassMobile('settings')" @click="activeTab = 'settings'">
            <i class="fas fa-cog"></i>
            <span>设置</span>
          </button>
        </div>
      </div>
    </nav>

    <!-- 主内容 -->
    <main class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <!-- 我的订阅 -->
      <div v-if="activeTab === 'subscription'" class="space-y-6">
        <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">我的订阅</h1>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">管理您的订阅链接和节点信息</p>
          </div>
          <button
            class="inline-flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-blue-500 to-purple-600 px-4 py-2.5 text-sm font-medium text-white shadow-lg shadow-blue-500/25 transition-all hover:shadow-xl hover:shadow-blue-500/30 disabled:opacity-50"
            :disabled="regenerating"
            @click="handleRegenerateToken"
          >
            <i class="fas fa-sync-alt" :class="{ 'animate-spin': regenerating }"></i>
            {{ regenerating ? '生成中...' : '重新生成链接' }}
          </button>
        </div>

        <!-- 流量仪表盘 -->
        <div
          class="overflow-hidden rounded-2xl border border-gray-200/50 bg-white/70 shadow-xl shadow-gray-200/50 backdrop-blur-sm dark:border-gray-700/50 dark:bg-gray-800/70 dark:shadow-none"
        >
          <div
            class="border-b border-gray-100 bg-gradient-to-r from-emerald-500/10 to-cyan-500/10 px-6 py-4 dark:border-gray-700/50"
          >
            <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
              <i class="fas fa-chart-pie text-emerald-500"></i>
              流量概览
            </h3>
          </div>
          <div class="p-6">
            <div v-if="userTraffic" class="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
              <!-- 已用流量 -->
              <div
                class="rounded-xl bg-gradient-to-br from-blue-50 to-blue-100/50 p-4 dark:from-blue-900/20 dark:to-blue-800/10"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-medium text-blue-600 dark:text-blue-400">已用流量</p>
                    <p class="mt-1 text-2xl font-bold text-blue-700 dark:text-blue-300">
                      {{ formatTraffic(userTraffic.trafficUsed) }}
                    </p>
                  </div>
                  <div
                    class="flex h-12 w-12 items-center justify-center rounded-full bg-blue-500/20"
                  >
                    <i class="fas fa-cloud-upload-alt text-xl text-blue-500"></i>
                  </div>
                </div>
              </div>

              <!-- 剩余流量 -->
              <div
                class="rounded-xl bg-gradient-to-br from-emerald-50 to-emerald-100/50 p-4 dark:from-emerald-900/20 dark:to-emerald-800/10"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-medium text-emerald-600 dark:text-emerald-400">
                      剩余流量
                    </p>
                    <p class="mt-1 text-2xl font-bold text-emerald-700 dark:text-emerald-300">
                      {{ formatTraffic(userTraffic.remaining) }}
                    </p>
                  </div>
                  <div
                    class="flex h-12 w-12 items-center justify-center rounded-full bg-emerald-500/20"
                  >
                    <i class="fas fa-cloud-download-alt text-xl text-emerald-500"></i>
                  </div>
                </div>
              </div>

              <!-- 总流量 -->
              <div
                class="rounded-xl bg-gradient-to-br from-purple-50 to-purple-100/50 p-4 dark:from-purple-900/20 dark:to-purple-800/10"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-medium text-purple-600 dark:text-purple-400">总流量</p>
                    <p class="mt-1 text-2xl font-bold text-purple-700 dark:text-purple-300">
                      {{ formatTraffic(userTraffic.trafficLimit) }}
                    </p>
                  </div>
                  <div
                    class="flex h-12 w-12 items-center justify-center rounded-full bg-purple-500/20"
                  >
                    <i class="fas fa-database text-xl text-purple-500"></i>
                  </div>
                </div>
              </div>

              <!-- 使用率 -->
              <div
                class="rounded-xl bg-gradient-to-br from-amber-50 to-amber-100/50 p-4 dark:from-amber-900/20 dark:to-amber-800/10"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-medium text-amber-600 dark:text-amber-400">使用率</p>
                    <p class="mt-1 text-2xl font-bold text-amber-700 dark:text-amber-300">
                      {{ userTraffic.usedPercent }}%
                    </p>
                  </div>
                  <div
                    class="flex h-12 w-12 items-center justify-center rounded-full bg-amber-500/20"
                  >
                    <i class="fas fa-percentage text-xl text-amber-500"></i>
                  </div>
                </div>
              </div>
            </div>

            <!-- 流量进度条 -->
            <div v-if="userTraffic" class="mt-6">
              <div class="flex items-center justify-between text-sm">
                <span class="text-gray-600 dark:text-gray-400">流量使用进度</span>
                <span class="font-medium text-gray-900 dark:text-white">
                  {{ formatTraffic(userTraffic.trafficUsed) }} /
                  {{ formatTraffic(userTraffic.trafficLimit) }}
                </span>
              </div>
              <div
                class="mt-2 h-3 w-full overflow-hidden rounded-full bg-gray-200 dark:bg-gray-700"
              >
                <div
                  class="h-3 rounded-full transition-all duration-500"
                  :class="
                    userTraffic.usedPercent > 90
                      ? 'bg-gradient-to-r from-red-500 to-red-600'
                      : userTraffic.usedPercent > 70
                        ? 'bg-gradient-to-r from-amber-500 to-orange-500'
                        : 'bg-gradient-to-r from-emerald-500 to-cyan-500'
                  "
                  :style="{ width: Math.min(100, userTraffic.usedPercent) + '%' }"
                ></div>
              </div>
              <div
                v-if="userTraffic.expiresAt"
                class="mt-2 text-xs text-gray-500 dark:text-gray-400"
              >
                <i class="fas fa-clock mr-1"></i>
                到期时间: {{ formatDate(userTraffic.expiresAt) }}
              </div>
            </div>

            <!-- 加载状态 -->
            <div v-else class="flex items-center justify-center py-8">
              <i class="fas fa-spinner fa-spin mr-2 text-blue-500"></i>
              <span class="text-gray-500">加载流量信息...</span>
            </div>
          </div>
        </div>

        <!-- 订阅链接卡片 -->
        <div
          class="overflow-hidden rounded-2xl border border-gray-200/50 bg-white/70 shadow-xl shadow-gray-200/50 backdrop-blur-sm dark:border-gray-700/50 dark:bg-gray-800/70 dark:shadow-none"
        >
          <div
            class="border-b border-gray-100 bg-gradient-to-r from-blue-500/10 to-purple-500/10 px-6 py-4 dark:border-gray-700/50"
          >
            <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
              <i class="fas fa-link text-blue-500"></i>
              订阅链接
            </h3>
          </div>
          <div v-if="subscription" class="p-6">
            <div v-if="subscription.subscriptionUrl" class="space-y-6">
              <!-- 通用订阅链接 -->
              <div class="space-y-3">
                <label class="text-sm font-medium text-gray-700 dark:text-gray-300"
                  >通用订阅地址</label
                >
                <div class="flex flex-col gap-2 sm:flex-row">
                  <input
                    class="flex-1 rounded-xl border border-gray-200 bg-gray-50/50 px-4 py-3 font-mono text-sm text-gray-700 dark:border-gray-600 dark:bg-gray-700/50 dark:text-gray-200"
                    readonly
                    :value="subscription.subscriptionUrl"
                  />
                  <div class="flex gap-2">
                    <button
                      class="inline-flex items-center justify-center gap-2 rounded-xl bg-blue-500 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-blue-600"
                      @click="copyUrl(subscription.subscriptionUrl)"
                    >
                      <i class="fas fa-copy"></i>
                      <span class="hidden sm:inline">复制</span>
                    </button>
                    <button
                      class="inline-flex items-center justify-center gap-2 rounded-xl bg-gray-100 px-4 py-2.5 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
                      @click="showQrCode(subscription.subscriptionUrl)"
                    >
                      <i class="fas fa-qrcode"></i>
                      <span class="hidden sm:inline">二维码</span>
                    </button>
                  </div>
                </div>
                <div
                  v-if="subscription.tokenStatus"
                  class="flex flex-wrap items-center gap-3 text-sm"
                >
                  <span
                    v-if="subscription.tokenStatus.oneTimeUse"
                    class="inline-flex items-center gap-1.5 rounded-full px-3 py-1"
                    :class="
                      subscription.tokenStatus.isConsumed
                        ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400'
                        : 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                    "
                  >
                    <i
                      :class="
                        subscription.tokenStatus.isConsumed
                          ? 'fas fa-times-circle'
                          : 'fas fa-check-circle'
                      "
                    ></i>
                    {{
                      subscription.tokenStatus.isConsumed ? '链接已失效' : '一次性链接（未使用）'
                    }}
                  </span>
                  <span
                    class="inline-flex items-center gap-1.5 rounded-full bg-gray-100 px-3 py-1 text-gray-600 dark:bg-gray-700 dark:text-gray-300"
                  >
                    <i class="fas fa-eye"></i>
                    访问次数: {{ subscription.tokenStatus.accessCount }}
                  </span>
                </div>
              </div>

              <!-- 多格式订阅链接 -->
              <div class="space-y-3">
                <label class="text-sm font-medium text-gray-700 dark:text-gray-300"
                  >客户端专用链接</label
                >
                <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  <div
                    v-for="format in subscriptionFormats"
                    :key="format.name"
                    class="group relative overflow-hidden rounded-xl border border-gray-200 bg-white p-4 transition-all hover:border-blue-300 hover:shadow-md dark:border-gray-700 dark:bg-gray-800 dark:hover:border-blue-600"
                  >
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-3">
                        <div
                          class="flex h-10 w-10 items-center justify-center rounded-lg"
                          :class="format.iconBg"
                        >
                          <i class="text-lg text-white" :class="format.icon"></i>
                        </div>
                        <div>
                          <div class="font-medium text-gray-900 dark:text-white">
                            {{ format.name }}
                          </div>
                          <div class="text-xs text-gray-500 dark:text-gray-400">
                            {{ format.desc }}
                          </div>
                        </div>
                      </div>
                      <div class="flex gap-1">
                        <button
                          class="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-100 hover:text-blue-500 dark:hover:bg-gray-700"
                          title="复制"
                          @click="copyUrl(getFormatUrl(format.type))"
                        >
                          <i class="fas fa-copy"></i>
                        </button>
                        <button
                          class="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-100 hover:text-purple-500 dark:hover:bg-gray-700"
                          title="二维码"
                          @click="showQrCode(getFormatUrl(format.type))"
                        >
                          <i class="fas fa-qrcode"></i>
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <div v-else class="flex flex-col items-center justify-center py-12 text-center">
              <div
                class="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-gray-100 dark:bg-gray-700"
              >
                <i class="fas fa-link-slash text-2xl text-gray-400"></i>
              </div>
              <p class="text-gray-500 dark:text-gray-400">暂无订阅链接</p>
              <button
                class="mt-4 rounded-xl bg-blue-500 px-4 py-2 text-sm text-white hover:bg-blue-600"
                @click="handleRegenerateToken"
              >
                生成订阅链接
              </button>
            </div>
          </div>
          <div v-else class="flex items-center justify-center py-12">
            <i class="fas fa-spinner fa-spin mr-2 text-blue-500"></i>
            <span class="text-gray-500">加载中...</span>
          </div>
        </div>

        <!-- 节点列表 -->
        <div
          class="overflow-hidden rounded-2xl border border-gray-200/50 bg-white/70 shadow-xl shadow-gray-200/50 backdrop-blur-sm dark:border-gray-700/50 dark:bg-gray-800/70 dark:shadow-none"
        >
          <div
            class="border-b border-gray-100 bg-gradient-to-r from-green-500/10 to-teal-500/10 px-6 py-4 dark:border-gray-700/50"
          >
            <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
              <i class="fas fa-server text-green-500"></i>
              可用节点
              <span
                class="ml-2 rounded-full bg-green-100 px-2 py-0.5 text-xs font-normal text-green-700 dark:bg-green-900/30 dark:text-green-400"
                >{{ nodes.length }} 个</span
              >
            </h3>
          </div>
          <div class="divide-y divide-gray-100 dark:divide-gray-700/50">
            <div
              v-for="node in nodes"
              :key="node.id"
              class="flex items-center justify-between p-4 transition-colors hover:bg-gray-50/50 dark:hover:bg-gray-700/30"
            >
              <div class="flex items-center gap-4">
                <div
                  class="flex h-10 w-10 items-center justify-center rounded-xl"
                  :class="getNodeTypeClass(node.type)"
                >
                  <i class="text-white" :class="getNodeTypeIcon(node.type)"></i>
                </div>
                <div>
                  <div class="font-medium text-gray-900 dark:text-white">{{ node.name }}</div>
                  <div class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
                    <span class="rounded bg-gray-100 px-1.5 py-0.5 text-xs dark:bg-gray-700">{{
                      node.type
                    }}</span>
                  </div>
                </div>
              </div>
              <div class="flex gap-2">
                <button
                  class="rounded-lg bg-gray-100 px-3 py-2 text-sm text-gray-700 transition-colors hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600"
                  @click="copyUrl(node.url)"
                >
                  <i class="fas fa-copy mr-1.5"></i>复制
                </button>
                <button
                  class="rounded-lg bg-gray-100 px-3 py-2 text-sm text-gray-700 transition-colors hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600"
                  @click="showQrCode(node.url)"
                >
                  <i class="fas fa-qrcode"></i>
                </button>
              </div>
            </div>
            <div
              v-if="nodes.length === 0"
              class="flex flex-col items-center justify-center py-12 text-center"
            >
              <i class="fas fa-server mb-4 text-4xl text-gray-300 dark:text-gray-600"></i>
              <p class="text-gray-500 dark:text-gray-400">暂无可用节点</p>
            </div>
          </div>
        </div>
      </div>

      <!-- 用户管理（管理员） -->
      <div v-else-if="activeTab === 'users' && subStore.isAdmin" class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold text-gray-900 dark:text-white">用户管理</h1>
            <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">管理您的下级用户</p>
          </div>
          <button
            class="rounded-md px-4 py-2 text-sm text-white"
            :class="
              adminStats && adminStats.remainingSlots <= 0
                ? 'cursor-not-allowed bg-gray-400'
                : 'bg-blue-600 hover:bg-blue-700'
            "
            :disabled="adminStats && adminStats.remainingSlots <= 0"
            @click="showCreateModal = true"
          >
            {{ adminStats && adminStats.remainingSlots <= 0 ? '已达上限' : '创建用户' }}
          </button>
        </div>

        <!-- 统计卡片 -->
        <div v-if="adminStats" class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <!-- 用户数量 -->
          <div class="rounded-lg bg-white p-4 shadow dark:bg-gray-800">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-500 dark:text-gray-400">下级用户</p>
                <p class="mt-1 text-2xl font-semibold text-gray-900 dark:text-white">
                  {{ adminStats.subUserCount }} / {{ adminStats.maxSubUsers }}
                </p>
              </div>
              <div class="rounded-full bg-blue-100 p-3 dark:bg-blue-900">
                <svg
                  class="h-6 w-6 text-blue-600 dark:text-blue-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                  />
                </svg>
              </div>
            </div>
            <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
              剩余可创建: {{ adminStats.remainingSlots }} 个
            </p>
          </div>

          <!-- 总流量使用 -->
          <div class="rounded-lg bg-white p-4 shadow dark:bg-gray-800">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-500 dark:text-gray-400">总流量使用</p>
                <p class="mt-1 text-2xl font-semibold text-gray-900 dark:text-white">
                  {{ formatTraffic(adminStats.totalTrafficUsed) }}
                </p>
              </div>
              <div class="rounded-full bg-green-100 p-3 dark:bg-green-900">
                <svg
                  class="h-6 w-6 text-green-600 dark:text-green-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                  />
                </svg>
              </div>
            </div>
            <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
              总配额: {{ formatTraffic(adminStats.totalTrafficLimit) }}
            </p>
          </div>

          <!-- 流量使用率 -->
          <div class="rounded-lg bg-white p-4 shadow dark:bg-gray-800">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-500 dark:text-gray-400">流量使用率</p>
                <p class="mt-1 text-2xl font-semibold text-gray-900 dark:text-white">
                  {{ adminStats.trafficUsedPercent }}%
                </p>
              </div>
              <div class="rounded-full bg-yellow-100 p-3 dark:bg-yellow-900">
                <svg
                  class="h-6 w-6 text-yellow-600 dark:text-yellow-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                  />
                </svg>
              </div>
            </div>
            <div class="mt-2 h-2 w-full rounded-full bg-gray-200 dark:bg-gray-700">
              <div
                class="h-2 rounded-full bg-yellow-500"
                :style="{ width: adminStats.trafficUsedPercent + '%' }"
              ></div>
            </div>
          </div>
        </div>

        <!-- 用户列表 -->
        <div class="overflow-hidden rounded-lg bg-white shadow dark:bg-gray-800">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <thead class="bg-gray-50 dark:bg-gray-700">
                <tr>
                  <th
                    class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-300"
                  >
                    用户名
                  </th>
                  <th
                    class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-300"
                  >
                    状态
                  </th>
                  <th
                    class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-300"
                  >
                    流量使用
                  </th>
                  <th
                    class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-300"
                  >
                    创建时间
                  </th>
                  <th
                    class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-300"
                  >
                    操作
                  </th>
                </tr>
              </thead>
              <tbody
                class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-800"
              >
                <tr v-for="user in subUsers" :key="user.id">
                  <td class="whitespace-nowrap px-6 py-4">
                    <div class="text-sm font-medium text-gray-900 dark:text-white">
                      {{ user.username }}
                    </div>
                    <div class="text-sm text-gray-500 dark:text-gray-400">{{ user.name }}</div>
                  </td>
                  <td class="whitespace-nowrap px-6 py-4">
                    <span
                      class="rounded-full px-2 py-1 text-xs"
                      :class="
                        user.isActive
                          ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                          : 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200'
                      "
                    >
                      {{ user.isActive ? '正常' : '禁用' }}
                    </span>
                  </td>
                  <td class="whitespace-nowrap px-6 py-4">
                    <div class="text-sm text-gray-900 dark:text-white">
                      {{ formatTraffic(user.trafficUsed) }} / {{ formatTraffic(user.trafficLimit) }}
                    </div>
                    <div class="mt-1 h-2 w-24 rounded-full bg-gray-200 dark:bg-gray-700">
                      <div
                        class="h-2 rounded-full"
                        :class="
                          getTrafficPercent(user.trafficUsed, user.trafficLimit) > 80
                            ? 'bg-red-500'
                            : getTrafficPercent(user.trafficUsed, user.trafficLimit) > 50
                              ? 'bg-yellow-500'
                              : 'bg-green-500'
                        "
                        :style="{
                          width: getTrafficPercent(user.trafficUsed, user.trafficLimit) + '%'
                        }"
                      ></div>
                    </div>
                    <div class="text-xs text-gray-500 dark:text-gray-400">
                      {{ getTrafficPercent(user.trafficUsed, user.trafficLimit) }}%
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
                    {{ formatDate(user.createdAt) }}
                  </td>
                  <td class="whitespace-nowrap px-6 py-4 text-sm">
                    <div class="flex flex-wrap gap-2">
                      <button
                        class="text-blue-600 hover:text-blue-800 dark:text-blue-400"
                        @click="handleResetPassword(user)"
                      >
                        重置密码
                      </button>
                      <button
                        class="text-purple-600 hover:text-purple-800 dark:text-purple-400"
                        @click="handleResetTraffic(user)"
                      >
                        重置流量
                      </button>
                      <button
                        class="text-green-600 hover:text-green-800 dark:text-green-400"
                        @click="handleRegenerateUserToken(user)"
                      >
                        重新生成链接
                      </button>
                      <button
                        class="text-red-600 hover:text-red-800 dark:text-red-400"
                        @click="handleDeleteUser(user)"
                      >
                        删除
                      </button>
                    </div>
                  </td>
                </tr>
                <tr v-if="subUsers.length === 0">
                  <td class="px-6 py-4 text-center text-gray-500 dark:text-gray-400" colspan="5">
                    暂无下级用户
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- 使用教程 -->
      <div v-else-if="activeTab === 'tutorial'" class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">使用教程</h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            了解如何在各种客户端中使用订阅链接
          </p>
        </div>

        <!-- 快速开始 -->
        <div
          class="overflow-hidden rounded-2xl border border-gray-200/50 bg-white/70 shadow-xl backdrop-blur-sm dark:border-gray-700/50 dark:bg-gray-800/70"
        >
          <div
            class="border-b border-gray-100 bg-gradient-to-r from-amber-500/10 to-orange-500/10 px-6 py-4 dark:border-gray-700/50"
          >
            <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
              <i class="fas fa-rocket text-amber-500"></i>
              快速开始
            </h3>
          </div>
          <div class="p-6">
            <div class="grid gap-4 sm:grid-cols-3">
              <div class="flex items-start gap-4 rounded-xl bg-gray-50 p-4 dark:bg-gray-700/50">
                <div
                  class="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-blue-500 text-lg font-bold text-white"
                >
                  1
                </div>
                <div>
                  <h4 class="font-medium text-gray-900 dark:text-white">复制订阅链接</h4>
                  <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    在"我的订阅"页面复制您的专属订阅链接
                  </p>
                </div>
              </div>
              <div class="flex items-start gap-4 rounded-xl bg-gray-50 p-4 dark:bg-gray-700/50">
                <div
                  class="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-purple-500 text-lg font-bold text-white"
                >
                  2
                </div>
                <div>
                  <h4 class="font-medium text-gray-900 dark:text-white">导入客户端</h4>
                  <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    在您的代理客户端中添加订阅链接
                  </p>
                </div>
              </div>
              <div class="flex items-start gap-4 rounded-xl bg-gray-50 p-4 dark:bg-gray-700/50">
                <div
                  class="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-green-500 text-lg font-bold text-white"
                >
                  3
                </div>
                <div>
                  <h4 class="font-medium text-gray-900 dark:text-white">开始使用</h4>
                  <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    选择节点并连接，享受高速网络
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- 客户端教程 -->
        <div class="grid gap-6 lg:grid-cols-2">
          <div
            v-for="tutorial in tutorials"
            :key="tutorial.name"
            class="overflow-hidden rounded-2xl border border-gray-200/50 bg-white/70 shadow-lg backdrop-blur-sm dark:border-gray-700/50 dark:bg-gray-800/70"
          >
            <div
              class="flex items-center gap-4 border-b border-gray-100 px-6 py-4 dark:border-gray-700/50"
            >
              <div
                class="flex h-12 w-12 items-center justify-center rounded-xl"
                :class="tutorial.iconBg"
              >
                <i class="text-xl text-white" :class="tutorial.icon"></i>
              </div>
              <div>
                <h3 class="font-semibold text-gray-900 dark:text-white">{{ tutorial.name }}</h3>
                <p class="text-sm text-gray-500 dark:text-gray-400">{{ tutorial.platform }}</p>
              </div>
            </div>
            <div class="p-6">
              <ol class="space-y-3">
                <li
                  v-for="(step, index) in tutorial.steps"
                  :key="index"
                  class="flex items-start gap-3"
                >
                  <span
                    class="flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full bg-gray-100 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-300"
                    >{{ index + 1 }}</span
                  >
                  <span class="text-sm text-gray-600 dark:text-gray-300">{{ step }}</span>
                </li>
              </ol>
              <a
                v-if="tutorial.downloadUrl"
                class="mt-4 inline-flex items-center gap-2 text-sm text-blue-500 hover:text-blue-600"
                :href="tutorial.downloadUrl"
                :download="tutorial.downloadUrl.split('/').pop()"
              >
                <i class="fas fa-download"></i>
                下载客户端
              </a>
            </div>
          </div>
        </div>

        <!-- 常见问题 -->
        <div
          class="overflow-hidden rounded-2xl border border-gray-200/50 bg-white/70 shadow-xl backdrop-blur-sm dark:border-gray-700/50 dark:bg-gray-800/70"
        >
          <div
            class="border-b border-gray-100 bg-gradient-to-r from-cyan-500/10 to-blue-500/10 px-6 py-4 dark:border-gray-700/50"
          >
            <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
              <i class="fas fa-question-circle text-cyan-500"></i>
              常见问题
            </h3>
          </div>
          <div class="divide-y divide-gray-100 dark:divide-gray-700/50">
            <div v-for="faq in faqs" :key="faq.q" class="p-6">
              <h4 class="font-medium text-gray-900 dark:text-white">{{ faq.q }}</h4>
              <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">{{ faq.a }}</p>
            </div>
          </div>
        </div>
      </div>

      <!-- 账号设置 -->
      <div v-else-if="activeTab === 'settings'" class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">账号设置</h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">修改您的账号密码</p>
        </div>

        <div
          class="overflow-hidden rounded-2xl border border-gray-200/50 bg-white/70 shadow-xl backdrop-blur-sm dark:border-gray-700/50 dark:bg-gray-800/70"
        >
          <div
            class="border-b border-gray-100 bg-gradient-to-r from-gray-500/10 to-slate-500/10 px-6 py-4 dark:border-gray-700/50"
          >
            <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
              <i class="fas fa-key text-gray-500"></i>
              修改密码
            </h3>
          </div>
          <div class="p-6">
            <form class="max-w-md space-y-4" @submit.prevent="handleChangePassword">
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300"
                  >原密码</label
                >
                <input
                  v-model="passwordForm.oldPassword"
                  class="mt-1 block w-full rounded-xl border border-gray-200 bg-gray-50/50 px-4 py-3 dark:border-gray-600 dark:bg-gray-700/50 dark:text-white"
                  required
                  type="password"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300"
                  >新密码</label
                >
                <input
                  v-model="passwordForm.newPassword"
                  class="mt-1 block w-full rounded-xl border border-gray-200 bg-gray-50/50 px-4 py-3 dark:border-gray-600 dark:bg-gray-700/50 dark:text-white"
                  minlength="6"
                  required
                  type="password"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300"
                  >确认新密码</label
                >
                <input
                  v-model="passwordForm.confirmPassword"
                  class="mt-1 block w-full rounded-xl border border-gray-200 bg-gray-50/50 px-4 py-3 dark:border-gray-600 dark:bg-gray-700/50 dark:text-white"
                  required
                  type="password"
                />
              </div>
              <button
                class="inline-flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-blue-500 to-purple-600 px-6 py-3 text-sm font-medium text-white shadow-lg shadow-blue-500/25 transition-all hover:shadow-xl disabled:opacity-50"
                :disabled="changingPassword"
                type="submit"
              >
                <i class="fas fa-save"></i>
                {{ changingPassword ? '修改中...' : '保存修改' }}
              </button>
            </form>
          </div>
        </div>
      </div>
    </main>

    <!-- 二维码弹窗 -->
    <div
      v-if="showQrModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm"
      @click.self="showQrModal = false"
    >
      <div
        class="mx-4 w-full max-w-sm overflow-hidden rounded-2xl bg-white shadow-2xl dark:bg-gray-800"
      >
        <div
          class="flex items-center justify-between border-b border-gray-100 px-6 py-4 dark:border-gray-700"
        >
          <h3 class="font-semibold text-gray-900 dark:text-white">扫码导入</h3>
          <button
            class="rounded-lg p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-700"
            @click="showQrModal = false"
          >
            <i class="fas fa-times"></i>
          </button>
        </div>
        <div class="flex flex-col items-center p-6">
          <div class="rounded-xl bg-white p-4 shadow-inner">
            <canvas ref="qrCanvas" class="h-48 w-48"></canvas>
          </div>
          <p class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
            使用客户端扫描二维码导入订阅
          </p>
          <button
            class="mt-4 inline-flex items-center gap-2 rounded-xl bg-blue-500 px-4 py-2 text-sm text-white hover:bg-blue-600"
            @click="copyUrl(qrCodeUrl)"
          >
            <i class="fas fa-copy"></i>
            复制链接
          </button>
        </div>
      </div>
    </div>

    <!-- 创建用户弹窗 -->
    <div
      v-if="showCreateModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50"
    >
      <div class="w-full max-w-md rounded-lg bg-white p-6 dark:bg-gray-800">
        <h3 class="text-lg font-medium text-gray-900 dark:text-white">创建下级用户</h3>
        <form class="mt-4 space-y-4" @submit.prevent="handleCreateUser">
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">用户名</label>
            <input
              v-model="createForm.username"
              class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              required
              type="text"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">密码</label>
            <input
              v-model="createForm.password"
              class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              minlength="6"
              required
              type="password"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300"
              >显示名称</label
            >
            <input
              v-model="createForm.name"
              class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              type="text"
            />
          </div>
          <div class="flex items-center">
            <input
              id="oneTimeUse"
              v-model="createForm.oneTimeUse"
              class="h-4 w-4 rounded border-gray-300"
              type="checkbox"
            />
            <label class="ml-2 text-sm text-gray-700 dark:text-gray-300" for="oneTimeUse"
              >一次性订阅链接（使用后失效）</label
            >
          </div>
          <div class="flex justify-end space-x-3">
            <button
              class="rounded-md border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300"
              type="button"
              @click="showCreateModal = false"
            >
              取消
            </button>
            <button
              class="rounded-md bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
              :disabled="creating"
              type="submit"
            >
              {{ creating ? '创建中...' : '创建' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- 重置密码弹窗 -->
    <div
      v-if="showResetModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50"
    >
      <div class="w-full max-w-md rounded-lg bg-white p-6 dark:bg-gray-800">
        <h3 class="text-lg font-medium text-gray-900 dark:text-white">
          重置密码 - {{ selectedUser?.username }}
        </h3>
        <form class="mt-4 space-y-4" @submit.prevent="confirmResetPassword">
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">新密码</label>
            <input
              v-model="resetForm.newPassword"
              class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              minlength="6"
              required
              type="password"
            />
          </div>
          <div class="flex justify-end space-x-3">
            <button
              class="rounded-md border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300"
              type="button"
              @click="showResetModal = false"
            >
              取消
            </button>
            <button
              class="rounded-md bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
              :disabled="resetting"
              type="submit"
            >
              {{ resetting ? '重置中...' : '确认重置' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { useSubscriptionStore } from '@/stores/subscription'
import { useThemeStore } from '@/stores/theme'
import { showToast } from '@/utils/toast'
import ThemeToggle from '@/components/common/ThemeToggle.vue'
import QRCode from 'qrcode'

const router = useRouter()
const subStore = useSubscriptionStore()
const themeStore = useThemeStore()

// 获取基础路径用于下载链接
const basePath = import.meta.env.BASE_URL

const activeTab = ref('subscription')
const subscription = ref(null)
const nodes = ref([])
const subUsers = ref([])
const adminStats = ref(null)
const userTraffic = ref(null)
const regenerating = ref(false)
const changingPassword = ref(false)
const creating = ref(false)
const resetting = ref(false)
const resettingTraffic = ref(false)
const showCreateModal = ref(false)
const showResetModal = ref(false)
const selectedUser = ref(null)

// 二维码相关
const showQrModal = ref(false)
const qrCodeUrl = ref('')
const qrCanvas = ref(null)

const passwordForm = reactive({ oldPassword: '', newPassword: '', confirmPassword: '' })
const createForm = reactive({ username: '', password: '', name: '', oneTimeUse: true })
const resetForm = reactive({ newPassword: '' })

// 多格式订阅配置
const subscriptionFormats = [
  {
    name: 'Clash',
    type: 'clash',
    desc: 'Clash/ClashX/CFW',
    icon: 'fas fa-bolt',
    iconBg: 'bg-gradient-to-br from-blue-500 to-cyan-500'
  },
  {
    name: 'V2Ray',
    type: 'v2ray',
    desc: 'V2RayN/V2RayNG',
    icon: 'fas fa-rocket',
    iconBg: 'bg-gradient-to-br from-purple-500 to-pink-500'
  },
  {
    name: 'Surge',
    type: 'surge',
    desc: 'Surge iOS/Mac',
    icon: 'fas fa-wave-square',
    iconBg: 'bg-gradient-to-br from-orange-500 to-red-500'
  },
  {
    name: 'Shadowrocket',
    type: 'shadowrocket',
    desc: 'iOS 小火箭',
    icon: 'fas fa-paper-plane',
    iconBg: 'bg-gradient-to-br from-green-500 to-teal-500'
  },
  {
    name: 'Quantumult X',
    type: 'quantumultx',
    desc: 'iOS 圈X',
    icon: 'fas fa-atom',
    iconBg: 'bg-gradient-to-br from-indigo-500 to-purple-500'
  },
  {
    name: 'Sing-box',
    type: 'singbox',
    desc: '通用格式',
    icon: 'fas fa-box',
    iconBg: 'bg-gradient-to-br from-gray-600 to-gray-800'
  }
]

// 客户端教程
const tutorials = [
  {
    name: 'Clash Verge',
    platform: 'Windows / macOS / Linux',
    icon: 'fas fa-desktop',
    iconBg: 'bg-gradient-to-br from-blue-500 to-cyan-500',
    steps: [
      '打开 Clash Verge，点击左侧"订阅"',
      '点击"新建"按钮',
      '粘贴订阅链接，点击"保存"',
      '选择节点并开启系统代理'
    ],
    downloadUrl: 'https://github.com/clash-verge-rev/clash-verge-rev/releases'
  },
  {
    name: 'V2RayN',
    platform: 'Windows',
    icon: 'fab fa-windows',
    iconBg: 'bg-gradient-to-br from-blue-600 to-blue-800',
    steps: [
      '打开 V2RayN，点击"订阅分组"',
      '点击"添加订阅"',
      '粘贴订阅链接，点击"确定"',
      '右键托盘图标，更新订阅'
    ],
    downloadUrl: `${basePath}v2rayN-windows-64-desktop.zip`
  },
  {
    name: 'Shadowrocket',
    platform: 'iOS',
    icon: 'fab fa-apple',
    iconBg: 'bg-gradient-to-br from-gray-700 to-gray-900',
    steps: [
      '打开 Shadowrocket，点击右上角"+"',
      '选择"类型"为"Subscribe"',
      '粘贴订阅链接，点击"完成"',
      '选择节点并开启连接'
    ],
    downloadUrl: null
  },
  {
    name: 'V2RayNG',
    platform: 'Android',
    icon: 'fab fa-android',
    iconBg: 'bg-gradient-to-br from-green-500 to-green-700',
    steps: [
      '打开 V2RayNG，点击右上角"+"',
      '选择"从剪贴板导入"或"订阅设置"',
      '添加订阅链接并更新',
      '选择节点并点击右下角连接'
    ],
    downloadUrl: `${basePath}v2rayNG_1.10.28_arm64-v8a.apk`
  }
]

// 常见问题
const faqs = [
  {
    q: '订阅链接无法更新怎么办？',
    a: '请检查网络连接，或尝试重新生成订阅链接。如果问题持续，请联系管理员。'
  },
  {
    q: '节点连接不上怎么办？',
    a: '请尝试切换其他节点，或检查本地防火墙设置。部分节点可能因维护暂时不可用。'
  },
  { q: '如何选择最快的节点？', a: '大多数客户端支持测速功能，可以测试延迟后选择最低延迟的节点。' },
  {
    q: '订阅链接可以分享给他人吗？',
    a: '不建议分享。每个订阅链接都与您的账号绑定，分享可能导致账号被封禁。'
  }
]

// 格式化流量显示
const formatTraffic = (bytes) => {
  if (!bytes || bytes === 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const k = 1024
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + units[i]
}

// 计算流量使用百分比
const getTrafficPercent = (used, limit) => {
  if (!limit || limit === 0) return 0
  return Math.min(100, ((used || 0) / limit) * 100).toFixed(1)
}

// 获取格式化的订阅链接
const getFormatUrl = (type) => {
  if (!subscription.value?.subscriptionUrl) return ''
  const baseUrl = subscription.value.subscriptionUrl
  return `${baseUrl}?format=${type}`
}

// 获取节点类型样式
const getNodeTypeClass = (type) => {
  const typeMap = {
    hysteria2: 'bg-gradient-to-br from-purple-500 to-pink-500',
    vless: 'bg-gradient-to-br from-blue-500 to-cyan-500',
    vmess: 'bg-gradient-to-br from-green-500 to-teal-500',
    trojan: 'bg-gradient-to-br from-red-500 to-orange-500',
    ss: 'bg-gradient-to-br from-gray-600 to-gray-800'
  }
  return typeMap[type?.toLowerCase()] || 'bg-gradient-to-br from-gray-500 to-gray-700'
}

// 获取节点类型图标
const getNodeTypeIcon = (type) => {
  const iconMap = {
    hysteria2: 'fas fa-bolt',
    vless: 'fas fa-shield-alt',
    vmess: 'fas fa-rocket',
    trojan: 'fas fa-horse',
    ss: 'fas fa-lock'
  }
  return iconMap[type?.toLowerCase()] || 'fas fa-server'
}

// 显示二维码
const showQrCode = async (url) => {
  qrCodeUrl.value = url
  showQrModal.value = true
  await nextTick()
  generateQrCode(url)
}

// 生成二维码
const generateQrCode = async (text) => {
  const canvas = qrCanvas.value
  if (!canvas) return

  try {
    await QRCode.toCanvas(canvas, text, {
      width: 192,
      margin: 2,
      color: {
        dark: '#000000',
        light: '#ffffff'
      }
    })
  } catch (err) {
    console.error('生成二维码失败:', err)
  }
}

const tabClass = (tab) => [
  'rounded-xl px-4 py-2 text-sm font-medium transition-all',
  activeTab.value === tab
    ? 'bg-gradient-to-r from-blue-500 to-purple-500 text-white shadow-lg shadow-blue-500/25'
    : 'text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700'
]

const tabClassMobile = (tab) => [
  'flex flex-col items-center gap-1 rounded-xl px-4 py-2 text-xs font-medium transition-all whitespace-nowrap',
  activeTab.value === tab
    ? 'bg-gradient-to-r from-blue-500 to-purple-500 text-white shadow-lg'
    : 'text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700'
]

const formatDate = (dateString) => {
  if (!dateString) return '-'
  return new Date(dateString).toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  })
}

const copyUrl = async (url) => {
  try {
    // 优先使用现代 Clipboard API（需要 HTTPS 或 localhost）
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(url)
      showToast('已复制到剪贴板', 'success')
      return
    }
    // 回退方案：使用传统的 execCommand（兼容 HTTP）
    const textArea = document.createElement('textarea')
    textArea.value = url
    textArea.style.position = 'fixed'
    textArea.style.left = '-9999px'
    textArea.style.top = '-9999px'
    document.body.appendChild(textArea)
    textArea.focus()
    textArea.select()
    const successful = document.execCommand('copy')
    document.body.removeChild(textArea)
    if (successful) {
      showToast('已复制到剪贴板', 'success')
    } else {
      showToast('复制失败，请手动复制', 'error')
    }
  } catch (e) {
    showToast('复制失败，请手动复制', 'error')
  }
}

const loadSubscription = async () => {
  try {
    subscription.value = await subStore.getSubscription()
  } catch (e) {
    console.error('Failed to load subscription:', e)
  }
}

const loadNodes = async () => {
  try {
    nodes.value = await subStore.getNodes()
  } catch (e) {
    console.error('Failed to load nodes:', e)
  }
}

const loadUserTraffic = async () => {
  try {
    userTraffic.value = await subStore.getUserTraffic()
  } catch (e) {
    console.error('Failed to load user traffic:', e)
  }
}

const loadSubUsers = async () => {
  if (!subStore.isAdmin) return
  try {
    const response = await subStore.getSubUsers()
    subUsers.value = response.data || []
    adminStats.value = response.stats || null
  } catch (e) {
    console.error('Failed to load sub users:', e)
  }
}

const handleRegenerateToken = async () => {
  regenerating.value = true
  try {
    const result = await subStore.regenerateToken()
    if (result.success) {
      showToast('订阅链接已重新生成', 'success')
      await loadSubscription()
    }
  } catch (e) {
    showToast(e.response?.data?.error || '重新生成失败', 'error')
  } finally {
    regenerating.value = false
  }
}

const handleChangePassword = async () => {
  if (passwordForm.newPassword !== passwordForm.confirmPassword) {
    showToast('两次输入的密码不一致', 'error')
    return
  }
  changingPassword.value = true
  try {
    await subStore.changePassword(passwordForm.oldPassword, passwordForm.newPassword)
    showToast('密码修改成功', 'success')
    passwordForm.oldPassword = ''
    passwordForm.newPassword = ''
    passwordForm.confirmPassword = ''
  } catch (e) {
    showToast(e.response?.data?.error || '修改失败', 'error')
  } finally {
    changingPassword.value = false
  }
}

const handleCreateUser = async () => {
  creating.value = true
  try {
    const result = await subStore.createSubUser(createForm)
    if (result.success) {
      showToast('用户创建成功', 'success')
      showCreateModal.value = false
      createForm.username = ''
      createForm.password = ''
      createForm.name = ''
      createForm.oneTimeUse = true
      await loadSubUsers()
    }
  } catch (e) {
    showToast(e.response?.data?.error || '创建失败', 'error')
  } finally {
    creating.value = false
  }
}

const handleResetPassword = (user) => {
  selectedUser.value = user
  resetForm.newPassword = ''
  showResetModal.value = true
}

const confirmResetPassword = async () => {
  resetting.value = true
  try {
    await subStore.resetSubUserPassword(selectedUser.value.id, resetForm.newPassword)
    showToast('密码重置成功', 'success')
    showResetModal.value = false
  } catch (e) {
    showToast(e.response?.data?.error || '重置失败', 'error')
  } finally {
    resetting.value = false
  }
}

const handleRegenerateUserToken = async (user) => {
  if (!confirm(`确定要为用户 ${user.username} 重新生成订阅链接吗？`)) return
  try {
    const result = await subStore.regenerateSubUserToken(user.id)
    if (result.success) {
      showToast('订阅链接已重新生成', 'success')
      await loadSubUsers()
    }
  } catch (e) {
    showToast(e.response?.data?.error || '重新生成失败', 'error')
  }
}

const handleDeleteUser = async (user) => {
  if (!confirm(`确定要删除用户 ${user.username} 吗？此操作不可恢复！`)) return
  try {
    await subStore.deleteSubUser(user.id)
    showToast('用户已删除', 'success')
    await loadSubUsers()
  } catch (e) {
    showToast(e.response?.data?.error || '删除失败', 'error')
  }
}

const handleResetTraffic = async (user) => {
  if (!confirm(`确定要重置用户 ${user.username} 的流量吗？`)) return
  resettingTraffic.value = true
  try {
    await subStore.resetSubUserTraffic(user.id)
    showToast('流量已重置', 'success')
    await loadSubUsers()
  } catch (e) {
    showToast(e.response?.data?.error || '重置失败', 'error')
  } finally {
    resettingTraffic.value = false
  }
}

const handleLogout = async () => {
  await subStore.logout()
  showToast('已退出登录', 'success')
  router.push('/sub-login')
}

onMounted(async () => {
  themeStore.initTheme()
  if (!subStore.isLoggedIn) {
    router.push('/sub-login')
    return
  }
  await Promise.all([loadSubscription(), loadNodes(), loadUserTraffic(), loadSubUsers()])
})
</script>
