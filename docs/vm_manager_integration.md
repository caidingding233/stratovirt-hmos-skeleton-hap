# HarmonyOS PC 虚拟化服务使用说明（vm_manager）

本文档面向应用开发者，总结 HarmonyOS PC 侧虚拟化服务（`vm_manager` + StratoVirt）的控制面 API、生命周期、限制条件与典型流程，定位为“类似 HVF 的使用说明 + 运行时约束文档”。  
接口与行为可能随系统版本与设备形态变化，请以实际环境为准。

## 1. 架构与责任边界

**控制面**与**执行面**分离：

- 应用（ETS/ArkTS）→ `virtService.vmManager`（NAPI 模块）
- Binder → `vm_manager` 系统能力
- `vm_manager` 拉起 **StratoVirt**（VMM）
- StratoVirt 访问 `/dev/hmv` / `/dev/kvm` 与 hypervisor 交互

结论：  
- App 仅通过 `vm_manager` 进行虚拟机管理，不提供直接 hypervisor 设备访问。  
- StratoVirt 是执行面（VMM），负责 vCPU、内存、中断等虚拟化实现。  
- 对应用而言，提供的是“管理型 API”，不是“hypervisor 级 API”。

## 2. 运行环境与限制

### 2.1 PC 模式门槛
`vm_manager` 依赖 **PC 模式** 与 **设备姿态**（如键盘/支架形态）：
- PC 模式（SceneBoard 管理）
- Tablet/二合一姿态状态

**结果**：未进入 PC 模式时，`checkVmCapability` 通常返回不支持。

### 2.2 权限与安全边界
系统侧有严格的权限校验：
- 普通应用不可直接访问 `/dev/hmv` / `/dev/kvm`
- 设备能力（摄像头/麦克风/剪贴板/文件访问等）受权限与用户授权限制
- 在 `libvm_manager.z.so` 中可见的权限字符串（非完整列表）：
  - `ohos.permission.CAMERA`
  - `ohos.permission.MICROPHONE`
  - `ohos.permission.sec.ACCESS_UDID`
- **即便 VM 已启动，后续操作仍可能触发权限校验**（例如窗口绑定、设备通道、数据通道），缺失权限会导致调用失败或 SA 被卸载。

### 2.3 独占窗口限制
- VM View 通常 **单实例绑定窗口**  
- 绑定失败会报 `The window already exists` / `WindowId err`  
- 独占模式依赖 `LockGuest` 与焦点事件，**无法多窗口并行绑定**

### 2.4 模块存在性与路径排查
当日志出现 `Load native module failed: @ohos:virtService.vmManager`、`libvmmanager_napi.z.so not exist` 等信息时，需要先确认 **模块是否随系统镜像打包**。

常见文件名/路径（不同版本可能有差异）：
- `/system/lib64/module/hms/virtservice/libvmmanager_napi.z.so`
- `/system/lib64/module/hms/virtservice/libvmmanagerinner_napi.z.so`
- `/system/lib64/module/hms/virtservice/vmmanager.abc`
- `/system/lib64/module/hms/virtservice/vmmanagerinner.abc`
- `/system/lib64/libvm_manager.z.so`
- `/system/lib64/libvm_manager_kits.z.so`
- 32 位或变体目录：`/system/lib/module/hms/virtservice/`、`/system/lib64/module/virtservice/`

执行面相关路径（StratoVirt/VMM）：
- `/system/bin/virt_service/vm_engine/stratovirt/stratovirt`
- `/system/opt/virt_service/`

无需 root 的替代检查（取决于系统是否开放命令与权限）：
1) **应用日志**：若出现 `Load native module failed`，说明 NAPI 模块未加载成功。  
2) **系统能力检查**（SA 65621）：  
   - `hdc shell "samgr list | grep 65621"`  
   - `hdc shell "hidumper -s 65621 | head -n 20"`  
3) **/system 读权限不足**：`Permission denied` 仅代表当前 shell 无读权限，**不能证明文件不存在**。

## 3. 生命周期与状态机

### 3.1 典型状态
- `STATE_CREATE` / `STATE_STARTING` / `STATE_RUNNING`
- `STATE_PAUSED` / `STATE_PAUSING` / `STATE_RESUMING`
- `STATE_STOPPING` / `STATE_STOPPED` / `STATE_DESTROY`
- `STATE_SNAPSHOTTING` / `STATE_UPDATE`

### 3.2 生命周期 API
- 创建：`createVm(vmName, cfg)`  
- 启动：`startVm(vmName, cfg)`  
- 暂停/恢复：`pauseVm` / `resumeVm`  
- 停止/销毁：`stopVm` / `destroyVm`  
- 强制停止：`forceStopVm`

## 4. ETS API 概览（控制面）

模块名：`@ohos.virtService.vmManager`

常用接口（非完整列表）：
- `createVm`, `startVm`, `stopVm`, `destroyVm`, `forceStopVm`
- `getVmStatus`, `getVmDiskSize`, `getVmDiskImagePath`
- `mountCDDriveToVm`, `unmountCDDriveFromVm`
- `importVmDiskImage`, `exportVmDiskImage`
- `createVmView`, `destroyVmView`, `setVmViewSize`
- `checkVmCapability`, `checkVmWindowVisible`
- `sendDataToVm`, `recvDataFromVm`

## 5. 关键数据结构（示例字段）

> 下列字段为常见配置项，实际支持情况与命名以系统版本为准。

### 5.1 CfgInfo（创建/启动 VM）
常见字段：
- `cpuNum`
- `memorySize`
- `diskSize`
- `netMode`（如 NAT/Bridge）
- `bridgeIp`
- `biosPath`（如 `stratovirt-uefi`）
- `enhanceFilePath`（增强工具路径，若支持）

### 5.2 ChannelInfo（通道/设备）
- `channelName`, `channelType`, `channels`
- 设备对象字段：`graphicDevice`, `audioDevice`, `networkDevice`, `keyboardMouseDevice`,
  `clipboardDevice`, `cameraDevice`, `storageDevice`

### 5.3 MigrationOptions
- `isKeepSnapshots`, `snapshotTime`, `diskSize`

### 5.4 USBDevice
- `deviceId` / `deviceInfo`（常见日志提示“device id is empty”）

## 6. 存储、镜像与 ISO

### 6.1 创建磁盘
- `createVm` + `diskSize` 触发系统创建磁盘镜像  
- 可通过 `getVmDiskImagePath` / `getVmDiskImageFileSize` 确认

### 6.2 扩容
- `setVmDiskSize` 或 `expandCapacity`（在部分实现中存在）

### 6.3 导入/导出磁盘
- `importVmDiskImage(vmName, options)`
- `exportVmDiskImage(vmName, options)`

### 6.4 ISO 挂载
- `mountCDDriveToVm(vmName, isoPath)`
- `unmountCDDriveFromVm(vmName, isoPath)`

推荐放置路径（系统共享目录示例）：  
`/docs/storage/Users/currentUser/.VMDocs/.hwf_share/`

## 7. VM View 与窗口

### 7.1 创建/销毁视图
- `createVmView(vmName, windowId, width, height)`
- `destroyVmView(windowId)`
- `setVmViewSize(width, height)`

### 7.2 分辨率同步
- `ModifyResolution(width, height)` 可用于让 guest 分辨率匹配宿主窗口

### 7.3 单窗口绑定
- VM View 绑定失败会提示：
  - `Failed to bind the surface to the window.`
  - `The window already exists.`
  - `WindowId err`

## 8. 独占模式（LockGuest + 焦点控制）

独占模式不是 PC 模式本身，而是运行期的控制链：

1) 进入 VM View → `FocusStateChangeEvent`  
2) `LockGuest`（锁定输入/焦点）  
3) `SleepLock / ScreenLock`（运行锁）  
4) QMP 侧调整策略（焦点/后台）  

因此独占模式下通常只允许**单窗口绑定**，退出多依赖系统手势。

## 9. 事件与回调

常见事件：
- `vmStateChange`（VM 状态变化）
- `vmViewStateChange`（VM 视图状态变化）
- `vmDiskMigration`, `vmDiskExported`
- `vmDataRecovery`

回调注册（应用侧接口提供）：
- VM 状态监听、视图状态监听、磁盘迁移监听
- 粘贴板与文件请求监听（guest/host 交互）

## 10. 增强工具与 WindowsFusion 通道

增强工具主要用于：
- 粘贴板同步
- 文件/目录请求
- 设备通道能力（如输入法/指针/图形）

当前提供的是基础融合能力（窗口、输入、粘贴板、文件请求）。  
如需应用级无缝融合或 NFC/ShareKit 转发，通常需要宿主应用自行集成。

## 11. 错误码（节选）

常见返回：
- `VM_OK`
- `VM_ERROR_INVALID_PARAM`
- `VM_ERROR_IPC_FAILED`
- `SA_VM_START_PARAM_INVALID`
- `SA_VM_MEMORY_LESS`
- `SA_VM_DISK_LESS`
- `STRATOVIRT_*` 系列错误（启动/渲染/设备）

## 12. 典型流程

### 12.1 安装新系统（ISO）
1. `createVm(vmName, cfg)`（含 `diskSize`）  
2. `mountCDDriveToVm(vmName, isoPath)`  
3. `startVm(vmName, cfg)`  
4. `createVmView(vmName, windowId, w, h)`  
5. `setVmViewSize(w, h)`  

### 12.2 导入已有磁盘
1. `importVmDiskImage(vmName, options)`  
2. `startVm(vmName, cfg)`  
3. `createVmView(...)`

### 12.3 独占 ↔ 窗口切换（受系统限制）
1. `destroyVmView` 释放当前绑定  
2. `createVmView` 绑定新窗口  
3. `FocusStateChangeEvent` 更新焦点  
4. 必要时调整 `setVmViewSize` / `ModifyResolution`

## 13. 排错指南

- **提示“not PC mode”**：需进入 PC 模式并满足姿态（支架/键盘）条件  
- **“window already exists”**：先 `destroyVmView` 再绑定  
- **权限不足/未授权**：检查系统权限与用户授权  
- **AccessToken 校验失败**（系统签名/白名单拦截）：  
  - 典型日志：`GetNativeTokenInfo TokenID ... is invalid`、`GetSingleton: can not get name`  
  - 含义：服务侧仅接受系统/原生 Token，普通 HAP 的 HapToken 会被拒绝  
  - 结果：调用返回失败或被系统卸载 SA（`PostDelayUnloadSATask: Unload SystemAbility VmManager SA Task`）  
- **`Load native module failed`**：优先排查 `virtservice` 模块是否随系统镜像打包，或被访问权限限制

## 14. 参考文档（openEuler）

- StratoVirt 介绍  
  https://docs.openeuler.org/en/docs/22.03_LTS/docs/StratoVirt/StratoVirt_introduction.html  
- VM 配置指南  
  https://docs.openeuler.org/en/docs/23.03/docs/StratoVirt/VM_configuration.html  
- 安装 StratoVirt  
  https://docs.openeuler.org/en/docs/22.09/docs/StratoVirt/Install_StratoVirt.html  
- VFIO 设备直通  
  https://docs.openeuler.org/en/docs/22.03_LTS/docs/StratoVirt/StratoVirt_VFIO_instructions.html  
- 与 libvirt 互通  
  https://docs.openeuler.org/en/docs/22.03_LTS_SP2/docs/StratoVirt/Interconnect_libvirt.html  

---

如需将文档进一步细化为“接口级参数签名”（含字段类型、默认值与错误码映射），可以在后续补充补丁版说明。
