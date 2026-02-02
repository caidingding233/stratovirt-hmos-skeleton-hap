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

开发侧注意点：
- `module.json5` 中需要声明 `requestPermissions`，并在 `usedScene` 写明使用场景
- **权限声明 ≠ 一定能用**：`vm_manager` 还会校验 AccessToken/白名单，普通 HAP 可能直接被拦截
- 若是系统应用，需要具备系统签名与系统级权限（`system_core` / `system_basic`）

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

### 2.5 能力探测与版本兼容
建议在运行期做能力探测与降级：
- `checkVmCapability()`：用于判断当前设备/模式是否允许 VM
- `getVmAvailableCpuNumRange()` / `getVmAvailableMemorySizeRange()`：用于探测硬件上限
- `getVmDiskImagePath()` / `getVmDiskImageFileSize()`：用于确认镜像是否已导入

若函数不存在或调用失败（如 `NOT_SUPPORT`），应退回到软件虚拟化/TCG 方案或提示设备不支持。

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

### 4.1 接口签名与类型信息（基于反编译/字符串）
> 说明：以下为 **已确认的函数名 + 推断的参数类型**。参数名以 NAPI key 及常见命名推断，**存在不确定项**。  
> 对于不确定项已标记「待确认」。

- `createVm(vmName: string, cfg: CfgInfo)`  
  - C++ 层存在 `CreateVm(string, string, sptr<CfgInfo>)` 的签名，**第二个 string 的语义待确认**（可能是镜像名/模板名/配置名）。
- `startVm(vmName: string, cfg: CfgInfo)`
- `stopVm(vmName: string)` / `destroyVm(vmName: string)` / `forceStopVm(vmName: string)`
- `getVmStatus(vmName: string): number`  
  - C++ 层是 `GetVmStatus(string, int&)`，ArkTS 侧一般映射为 Promise resolve 数值。
- `getVmDiskImagePath(vmName: string): string`
- `getVmDiskImageFileSize(vmName: string): number`
- `getVmDiskSize(vmName: string): number`
- `setVmDiskSize(vmName: string, size: number)`
- `importVmDiskImage(vmName: string, options: MigrationOptions | object)`  
  - C++ 层存在 `ImportVmDiskImage(string, string, string, sptr<MigrationOptions>)`，**三个 string 的语义待确认**（可能是 srcPath/dstPath/alias）。
  - NAPI 日志里明确出现 `guestOSImagePath`，说明参数对象内**存在该字段**（缺失会提示“failed to convert parameter to guestOSImagePath”）。
- `exportVmDiskImage(vmName: string, options: MigrationOptions | object)`
- `createVmView(vmName: string, windowId: number, width: number, height: number)`
- `destroyVmView(windowId: number)`
- `setVmViewSize(width: number, height: number)`
- `mountCDDriveToVm(vmName: string, isoPath: string)` / `unmountCDDriveFromVm(vmName: string, isoPath: string)`

### 4.2 异步模型与调用语义（待确认项与建议）
NAPI/ArkTS 层的 **Promise/回调模型未在符号中直接体现**，建议以运行期方式确认：
- 若返回对象存在 `then/catch`，即为 Promise；否则按回调或同步返回处理。
- `createVm` 不一定等同于“已运行”，通常需监听 `vmStateChange`，等待进入 `STATE_RUNNING`。

推荐做法：
1) `await createVm(...)`  
2) `await startVm(...)`  
3) 监听 `vmStateChange`，确认 `STATE_RUNNING` 后再创建 VM View

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

常见类型推断：
- `cpuNum`, `memorySize`, `diskSize`：`number`
- `netMode`: `number | string`（常见 `MODE_NAT` / `MODE_BRIDGE`）
- `bridgeIp`, `biosPath`, `enhanceFilePath`: `string`

必选项与默认值（经验建议）：
- 建议至少提供 `cpuNum` / `memorySize` / `diskSize`，否则可能触发 `SA_VM_START_PARAM_INVALID`
- 其他字段默认值与可选性依赖系统版本，需在运行期验证

### 5.2 ChannelInfo（通道/设备）
- `channelName`, `channelType`, `channels`
- 设备对象字段：`graphicDevice`, `audioDevice`, `networkDevice`, `keyboardMouseDevice`,
  `clipboardDevice`, `cameraDevice`, `storageDevice`

### 5.3 MigrationOptions
- `isKeepSnapshots`, `snapshotTime`, `diskSize`

### 5.4 USBDevice
- `deviceId` / `deviceInfo`（常见日志提示“device id is empty”）

### 5.5 NAPI 字段全集（从二进制抽取）
> 下列为从 `libvmmanager_napi.z.so` 提取到的 **全部 lowerCamel 字段**，包含 API 名、事件名与对象字段。  
> 其中部分字段语义未明（如 `cd9` 系列），建议按“存在字段”处理。

**API / 动作名**
- `createVm`, `startVm`, `stopVm`, `destroyVm`, `forceStopVm`
- `getVmStatus`, `getVmDiskSize`, `getVmDiskImagePath`, `getVmDiskImageFileSize`
- `setVmDiskSize`, `importVmDiskImage`, `exportVmDiskImage`
- `createVmView`, `destroyVmView`, `setVmViewSize`
- `createSnapshot`, `restoreSnapshot`, `destroySnapshot`, `renameSnapshot`, `getSnapshotList`
- `mountCDDriveToVm`, `unmountCDDriveFromVm`, `mountUSBToVm`, `unmountUSBFromVm`
- `checkVmCapability`, `checkVmWindowVisible`
- `createChannel`, `sendDataToVm`, `recvDataFromVm`
- `addSharedFolder`, `removeSharedFolder`
- `getVmAvailableCpuNumRange`, `getVmAvailableMemorySizeRange`
- `getHostSN`, `getFileDescriptorRequest`
- `recoverUserData`
- `setProxyAutoSyncEnabled`, `setVmNetProxyShareEnabled`
- `isHostNetworkSyncFeatureEnabled`, `isVmNetProxyEnabled`

**配置 / 参数对象字段**
- `cpuNum`, `memorySize`, `diskSize`
- `netMode`, `bridgeIp`
- `biosPath`, `enhanceFilePath`
- `snapshotTime`, `isKeepSnapshots`
- `guestOSImagePath`（导入磁盘必需字段，缺失会报错）

**Channel / Device 字段**
- `channelInfo`, `channelName`, `channelType`, `channels`
- `graphicDevice`, `audioDevice`, `networkDevice`, `keyboardMouseDevice`
- `clipboardDevice`, `cameraDevice`, `storageDevice`
- `inputDevice`, `outputDevice`, `memoryBalloonDevice`, `connectionDevice`

**事件 / 回调名**
- `vmStateChange`, `vmViewStateChange`
- `vmDiskMigration`, `vmDiskExported`
- `vmDataRecovery`, `tabletSwitchStateChange`

**其他字段（语义未明/内部）**
- `pasteboard`, `processUriInMultipleRecord`
- `proxyAutoSyncEnabled`, `setResolutionFail`
- `cD9`, `cd9`, `cd9H`, `cd9h`
- `storageType`, `SystemShare`, `SYSTEM_SHARE`

## 6. 存储、镜像与 ISO

### 6.1 创建磁盘
- `createVm` + `diskSize` 触发系统创建磁盘镜像  
- 可通过 `getVmDiskImagePath` / `getVmDiskImageFileSize` 确认

### 6.2 扩容
- `setVmDiskSize` 或 `expandCapacity`（在部分实现中存在）

### 6.3 导入/导出磁盘
- `importVmDiskImage(vmName, options)`
- `exportVmDiskImage(vmName, options)`

建议流程（使用自有 qcow2）：
1) 将 qcow2 放入**系统允许读取的目录**（受权限/SELinux 约束）  
2) 调用 `importVmDiskImage` 导入  
3) 用 `getVmDiskImagePath` / `getVmDiskImageFileSize` 验证导入结果  
4) `startVm` → `createVmView`

注意：
- `vm_manager` 通常不会直接使用任意路径，而是**导入到其受控目录**再启动  
- 部分实现会做 **qcow2 → raw** 转换（日志中可见相关提示）

参数推断（基于 NAPI 字符串）：
- `guestOSImagePath: string`（必需，缺失会报 *failed to convert parameter to guestOSImagePath*）
- `isKeepSnapshots?: boolean`
- `snapshotTime?: number`
- `diskSize?: number`

路径校验（疑似白名单前缀，需实机验证）：
- `file://docs/storage/Users/currentUser/`
- `file://docs/storage/External/`
- `/hmdfs/account/files/Docs/`
- `/local/files/Docs/`
- `/mnt/data/external/`
- `/docs/storage/Users/currentUser/.VMDocs/.hwf_share/`

若路径不合规，常见错误包括：`Invalid file path` / `Invalid path` / `share path is private sandbox path` / `share path is not authorized`。

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

### 9.1 事件 payload 获取方法（建议做法）
事件 payload 字段在库中未显式暴露文档化信息，建议在实际运行时直接打印对象：
```ts
vmManager.on('vmStateChange', (evt: any) => {
  console.info('[vmStateChange]', JSON.stringify(evt))
})
vmManager.on('vmViewStateChange', (evt: any) => {
  console.info('[vmViewStateChange]', JSON.stringify(evt))
})
```

常见枚举值（来自字符串与日志）：
- VM 状态：`STATE_CREATE` / `STATE_STARTING` / `STATE_RUNNING` / `STATE_STOPPED` 等
- View 状态：`vmViewStateChange`（具体值需运行期打印确认）

### 9.2 状态/枚举（从二进制抽取）
**VM 状态枚举**
- `STATE_AVAILABLE`, `STATE_UNAVAILABLE`, `STATE_CREATE`, `STATE_STARTING`, `STATE_RUNNING`
- `STATE_PAUSING`, `STATE_PAUSED`, `STATE_RESUMING`
- `STATE_STOPPING`, `STATE_STOPPED`, `STATE_DESTROY`
- `STATE_SNAPSHOTTING`, `STATE_UPDATE`, `STATE_VIEWING`, `STATE_ERROR`

**网络与通道枚举**
- `MODE_NAT`, `MODE_BRIDGE`
- `ChannelType`（常见 `TYPE_USB`, `TYPE_VIRTIO`）
- `NetMode`, `StorageType`, `EventType`, `VmErrorCode`, `VmState`, `VmViewState`

## 10. 增强工具与 WindowsFusion 通道

增强工具主要用于：
- 粘贴板同步
- 文件/目录请求
- 设备通道能力（如输入法/指针/图形）

当前提供的是基础融合能力（窗口、输入、粘贴板、文件请求）。  
如需应用级无缝融合或 NFC/ShareKit 转发，通常需要宿主应用自行集成。

### 10.1 Channel/Device 协议说明（现有资料的边界）
已知存在的对象/字段（来自 NAPI key）：
- `ChannelInfo`: `channelName`, `channelType`, `channels`
- 设备对象：`graphicDevice`, `audioDevice`, `networkDevice`, `keyboardMouseDevice`,
  `clipboardDevice`, `cameraDevice`, `storageDevice`, `memoryBalloonDevice`
- 数据通道：`sendDataToVm`, `recvDataFromVm`

**协议格式未在库内显式公开**，需要结合 guest 侧“增强工具/融合服务”实现或通过运行时抓包确认。

## 11. 错误码（节选）

常见返回：
- `VM_OK`
- `VM_ERROR_INVALID_PARAM`
- `VM_ERROR_IPC_FAILED`
- `SA_VM_START_PARAM_INVALID`
- `SA_VM_MEMORY_LESS`
- `SA_VM_DISK_LESS`
- `STRATOVIRT_*` 系列错误（启动/渲染/设备）

### 11.1 错误返回形态（待确认）
错误数值与返回结构未在公开文档中给出，建议做法：
- Promise 模式：`try/catch` 捕获异常对象，打印 `code` / `message`
- 回调模式：在回调参数中打印 `err` 或 `status`

可在日志中发现的典型失败文本：
- `permission denied`（权限/白名单/AccessToken 拦截）
- `WriteInterfaceToken failed`（IPC 失败）
- `GetVmDiskImageFileSize failed`（镜像路径或权限问题）

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

### 12.4 ArkTS 代码（create → start → view）
```ts
import vmManager from '@ohos.virtService.vmManager'

const vmName = 'demo'
const cfg = {
  cpuNum: 2,
  memorySize: 4096,
  diskSize: 64 * 1024, // MB，具体单位需运行期确认
  netMode: 'MODE_NAT',
}

try {
  await vmManager.createVm(vmName, cfg)
  await vmManager.startVm(vmName, cfg)
  vmManager.on('vmStateChange', (evt: any) => {
    console.info('state:', JSON.stringify(evt))
  })
  vmManager.createVmView(vmName, /*windowId*/ 1001, 1280, 720)
} catch (e) {
  console.error('vm error:', JSON.stringify(e))
}
```

## 13. 排错指南

- **提示“not PC mode”**：需进入 PC 模式并满足姿态（支架/键盘）条件  
- **“window already exists”**：先 `destroyVmView` 再绑定  
- **权限不足/未授权**：检查系统权限与用户授权  
- **AccessToken 校验失败**（系统签名/白名单拦截）：  
  - 典型日志：`GetNativeTokenInfo TokenID ... is invalid`、`GetSingleton: can not get name`  
  - 含义：服务侧仅接受系统/原生 Token，普通 HAP 的 HapToken 会被拒绝  
  - 结果：调用返回失败或被系统卸载 SA（`PostDelayUnloadSATask: Unload SystemAbility VmManager SA Task`）  
- **`Load native module failed`**：优先排查 `virtservice` 模块是否随系统镜像打包，或被访问权限限制

## 14. 限制与测试建议

- **资源上限**：以 `getVmAvailableCpuNumRange` / `getVmAvailableMemorySizeRange` 为准  
- **磁盘大小**：建议先 `getVmDiskSize`，扩容用 `setVmDiskSize`  
- **并发 View**：通常只允许单窗口绑定，建议做冲突处理  
- **性能与稳定性**：建议测试矩阵覆盖 CPU/内存/磁盘大小、窗口尺寸与多次启动/停止

## 15. 参考文档（openEuler）

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
