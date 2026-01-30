/// <reference path="../vmManager.d.ts" />
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import vmManager from '@ohos.virtService.vmManager';

const DOMAIN = 0x0000;

type VmValue = string | number | boolean | null;
interface VmGenericResult {
  code?: number;
  message?: string;
  data?: string;
}
type VmResult = VmValue | VmGenericResult | undefined;

interface VmCfgInfo {
  cpuNum: number;
  memorySize: number;
  diskSize: number;
}

type VmEventType = 'vmStateChange' | 'vmViewStateChange';

interface VmEventPayload {
  vmName?: string;
  state?: string;
  windowId?: number;
}

interface VmManagerApi {
  checkVmCapability: () => VmResult | Promise<VmResult>;
  getVmStatus: (vmName: string) => VmResult | Promise<VmResult>;
  createVm: (vmName: string, cfg: VmCfgInfo) => VmResult | Promise<VmResult>;
  startVm: (vmName: string, cfg: VmCfgInfo) => VmResult | Promise<VmResult>;
  pauseVm: (vmName: string) => VmResult | Promise<VmResult>;
  resumeVm: (vmName: string) => VmResult | Promise<VmResult>;
  stopVm: (vmName: string) => VmResult | Promise<VmResult>;
  forceStopVm: (vmName: string) => VmResult | Promise<VmResult>;
  destroyVm: (vmName: string) => VmResult | Promise<VmResult>;
  mountCDDriveToVm: (vmName: string, isoPath: string) => VmResult | Promise<VmResult>;
  unmountCDDriveFromVm: (vmName: string, isoPath: string) => VmResult | Promise<VmResult>;
  createVmView: (vmName: string, windowId: number, width: number, height: number) => VmResult | Promise<VmResult>;
  destroyVmView: (windowId: number) => VmResult | Promise<VmResult>;
  setVmViewSize: (width: number, height: number) => VmResult | Promise<VmResult>;
  sendDataToVm: (vmName: string, payload: string) => VmResult | Promise<VmResult>;
  recvDataFromVm: (vmName: string) => VmResult | Promise<VmResult>;
  getVmDiskImagePath: (vmName: string) => VmResult | Promise<VmResult>;
  getVmDiskSize: (vmName: string) => VmResult | Promise<VmResult>;
  on?: (event: VmEventType, callback: (data: VmEventPayload) => void) => void;
}

@Entry
@Component
struct Index {
  @State vmName: string = 'demo_vm';
  @State cpuNum: string = '4';
  @State memorySize: string = '4096';
  @State diskSize: string = '40';
  @State isoPath: string = '';
  @State sendPayload: string = 'ping';
  @State viewWidth: string = '1280';
  @State viewHeight: string = '720';
  @State status: string = 'Ready';
  @State windowId: number = -1;
  @State logs: string[] = [];

  private readonly vm: VmManagerApi | undefined = (typeof vmManager === 'object' && vmManager !== null)
    ? (vmManager as VmManagerApi)
    : undefined;

  aboutToAppear(): void {
    this.initVmEvents();
  }

  private initVmEvents(): void {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    const on = vm.on;
    if (!on) {
      this.appendLog('vmManager.on is not available');
      return;
    }
    on('vmStateChange', (data: VmEventPayload) => {
      this.appendLog(`vmStateChange: ${JSON.stringify(data)}`);
    });
    on('vmViewStateChange', (data: VmEventPayload) => {
      this.appendLog(`vmViewStateChange: ${JSON.stringify(data)}`);
    });
  }

  private appendLog(message: string): void {
    const now = new Date();
    const hh = now.getHours().toString().padStart(2, '0');
    const mm = now.getMinutes().toString().padStart(2, '0');
    const ss = now.getSeconds().toString().padStart(2, '0');
    const entry = `[${hh}:${mm}:${ss}] ${message}`;
    const next = [...this.logs, entry];
    this.logs = next.slice(-200);
    hilog.info(DOMAIN, 'vmDemo', '%{public}s', message);
  }

  private toInt(value: string, fallback: number, min: number, max: number): number {
    const parsed = Number.parseInt(value, 10);
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    return Math.min(Math.max(parsed, min), max);
  }

  private ensureVmName(): boolean {
    if (this.vmName.trim().length === 0) {
      this.setStatus('VM name is empty');
      return false;
    }
    return true;
  }

  private getVmOrWarn(): VmManagerApi | undefined {
    const vm = this.vm;
    if (!vm || typeof vm.checkVmCapability !== 'function') {
      this.setStatus('vmManager not available (native module missing or not exposed)');
      return undefined;
    }
    return vm;
  }

  private setStatus(message: string): void {
    this.status = message;
    this.appendLog(message);
  }

  private buildCfg(): VmCfgInfo {
    return {
      cpuNum: this.toInt(this.cpuNum, 2, 1, 32),
      memorySize: this.toInt(this.memorySize, 2048, 512, 262144),
      diskSize: this.toInt(this.diskSize, 40, 8, 2048),
    };
  }

  private async resolve(result: VmResult | Promise<VmResult>): Promise<VmResult> {
    if (result instanceof Promise) {
      return await result;
    }
    return result;
  }

  private async handleCheckCapability(): Promise<void> {
    try {
      const vm = this.getVmOrWarn();
      if (!vm) {
        return;
      }
      const result = await this.resolve(vm.checkVmCapability());
      this.setStatus(`checkVmCapability: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`checkVmCapability failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleGetStatus(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const result = await this.resolve(vm.getVmStatus(this.vmName));
      this.setStatus(`getVmStatus: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`getVmStatus failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleCreateVm(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const cfg = this.buildCfg();
      const result = await this.resolve(vm.createVm(this.vmName, cfg));
      this.setStatus(`createVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`createVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleStartVm(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const cfg = this.buildCfg();
      const result = await this.resolve(vm.startVm(this.vmName, cfg));
      this.setStatus(`startVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`startVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handlePauseVm(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const result = await this.resolve(vm.pauseVm(this.vmName));
      this.setStatus(`pauseVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`pauseVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleResumeVm(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const result = await this.resolve(vm.resumeVm(this.vmName));
      this.setStatus(`resumeVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`resumeVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleStopVm(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const result = await this.resolve(vm.stopVm(this.vmName));
      this.setStatus(`stopVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`stopVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleForceStopVm(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const result = await this.resolve(vm.forceStopVm(this.vmName));
      this.setStatus(`forceStopVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`forceStopVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleDestroyVm(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const result = await this.resolve(vm.destroyVm(this.vmName));
      this.setStatus(`destroyVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`destroyVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleMountIso(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    const isoPath = this.isoPath.trim();
    if (!isoPath) {
      this.setStatus('ISO path is empty');
      return;
    }
    try {
      const result = await this.resolve(vm.mountCDDriveToVm(this.vmName, isoPath));
      this.setStatus(`mountCDDriveToVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`mountCDDriveToVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleUnmountIso(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    const isoPath = this.isoPath.trim();
    if (!isoPath) {
      this.setStatus('ISO path is empty');
      return;
    }
    try {
      const result = await this.resolve(vm.unmountCDDriveFromVm(this.vmName, isoPath));
      this.setStatus(`unmountCDDriveFromVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`unmountCDDriveFromVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleCreateView(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const ctx = getContext(this);
      const win = await window.getLastWindow(ctx);
      const props = win.getWindowProperties();
      const winId = props.id;
      if (winId <= 0) {
        this.setStatus('windowId not available');
        return;
      }
      this.windowId = winId;
      const width = this.toInt(this.viewWidth, 1280, 320, 3840);
      const height = this.toInt(this.viewHeight, 720, 240, 2160);
      const result = await this.resolve(vm.createVmView(this.vmName, winId, width, height));
      this.setStatus(`createVmView: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`createVmView failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleDestroyView(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    const winId = this.windowId;
    if (winId < 0) {
      this.setStatus('windowId not set');
      return;
    }
    try {
      const result = await this.resolve(vm.destroyVmView(winId));
      this.setStatus(`destroyVmView: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`destroyVmView failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleResizeView(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    const width = this.toInt(this.viewWidth, 1280, 320, 3840);
    const height = this.toInt(this.viewHeight, 720, 240, 2160);
    try {
      const result = await this.resolve(vm.setVmViewSize(width, height));
      this.setStatus(`setVmViewSize: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`setVmViewSize failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleSendData(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    const payload = this.sendPayload.trim();
    if (!payload) {
      this.setStatus('payload is empty');
      return;
    }
    try {
      const result = await this.resolve(vm.sendDataToVm(this.vmName, payload));
      this.setStatus(`sendDataToVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`sendDataToVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleRecvData(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const result = await this.resolve(vm.recvDataFromVm(this.vmName));
      this.setStatus(`recvDataFromVm: ${JSON.stringify(result)}`);
    } catch (err) {
      this.setStatus(`recvDataFromVm failed: ${JSON.stringify(err)}`);
    }
  }

  private async handleGetDiskInfo(): Promise<void> {
    const vm = this.getVmOrWarn();
    if (!vm) {
      return;
    }
    if (!this.ensureVmName()) {
      return;
    }
    try {
      const path = await this.resolve(vm.getVmDiskImagePath(this.vmName));
      const size = await this.resolve(vm.getVmDiskSize(this.vmName));
      this.setStatus(`diskPath: ${JSON.stringify(path)}, diskSize: ${JSON.stringify(size)}`);
    } catch (err) {
      this.setStatus(`getVmDiskInfo failed: ${JSON.stringify(err)}`);
    }
  }

  build() {
    Scroll() {
      Column() {
        Text('StratoVirt VM Console')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
        Text(`Status: ${this.status}`)
          .fontSize(14)
          .margin({ top: 4 })
        Text(`WindowId: ${this.windowId >= 0 ? this.windowId : 'N/A'}`)
          .fontSize(12)
          .margin({ bottom: 8 })

        Divider()

        Row() {
          Text('VM Name').width(90)
          TextInput({ text: this.vmName, placeholder: 'demo_vm' })
            .onChange((value) => (this.vmName = value))
            .layoutWeight(1)
        }
        .margin({ top: 8 })

        Row() {
          Text('CPU').width(90)
          TextInput({ text: this.cpuNum, placeholder: '4' })
            .onChange((value) => (this.cpuNum = value))
            .layoutWeight(1)
        }
        .margin({ top: 6 })

        Row() {
          Text('Memory MB').width(90)
          TextInput({ text: this.memorySize, placeholder: '4096' })
            .onChange((value) => (this.memorySize = value))
            .layoutWeight(1)
        }
        .margin({ top: 6 })

        Row() {
          Text('Disk GB').width(90)
          TextInput({ text: this.diskSize, placeholder: '40' })
            .onChange((value) => (this.diskSize = value))
            .layoutWeight(1)
        }
        .margin({ top: 6 })

        Row() {
          Text('ISO Path').width(90)
          TextInput({ text: this.isoPath, placeholder: '/docs/storage/.../os.iso' })
            .onChange((value) => (this.isoPath = value))
            .layoutWeight(1)
        }
        .margin({ top: 6 })

        Row() {
          Text('View Size').width(90)
          TextInput({ text: this.viewWidth, placeholder: '1280' })
            .onChange((value) => (this.viewWidth = value))
            .layoutWeight(1)
          Text('x').margin({ left: 6, right: 6 })
          TextInput({ text: this.viewHeight, placeholder: '720' })
            .onChange((value) => (this.viewHeight = value))
            .layoutWeight(1)
        }
        .margin({ top: 6 })

        Row() {
          Text('Payload').width(90)
          TextInput({ text: this.sendPayload, placeholder: 'ping' })
            .onChange((value) => (this.sendPayload = value))
            .layoutWeight(1)
        }
        .margin({ top: 6 })

        Divider().margin({ top: 10, bottom: 6 })

        Row() {
          Button('Check Capability')
            .onClick(() => {
              void this.handleCheckCapability();
            })
          Button('Get Status')
            .onClick(() => {
              void this.handleGetStatus();
            })
          Button('Create VM')
            .onClick(() => {
              void this.handleCreateVm();
            })
        }
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Button('Start')
            .onClick(() => {
              void this.handleStartVm();
            })
          Button('Pause')
            .onClick(() => {
              void this.handlePauseVm();
            })
          Button('Resume')
            .onClick(() => {
              void this.handleResumeVm();
            })
          Button('Stop')
            .onClick(() => {
              void this.handleStopVm();
            })
        }
        .margin({ top: 6 })
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Button('Force Stop')
            .onClick(() => {
              void this.handleForceStopVm();
            })
          Button('Destroy VM')
            .onClick(() => {
              void this.handleDestroyVm();
            })
          Button('Disk Info')
            .onClick(() => {
              void this.handleGetDiskInfo();
            })
        }
        .margin({ top: 6 })
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Button('Mount ISO')
            .onClick(() => {
              void this.handleMountIso();
            })
          Button('Unmount ISO')
            .onClick(() => {
              void this.handleUnmountIso();
            })
          Button('Create View')
            .onClick(() => {
              void this.handleCreateView();
            })
        }
        .margin({ top: 6 })
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Button('Destroy View')
            .onClick(() => {
              void this.handleDestroyView();
            })
          Button('Resize View')
            .onClick(() => {
              void this.handleResizeView();
            })
          Button('Send Data')
            .onClick(() => {
              void this.handleSendData();
            })
        }
        .margin({ top: 6 })
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Button('Recv Data')
            .onClick(() => {
              void this.handleRecvData();
            })
        }
        .margin({ top: 6 })

        Divider().margin({ top: 10, bottom: 6 })

        Text('Logs').fontWeight(FontWeight.Bold)
        Scroll() {
          Column() {
            ForEach(this.logs, (item: string, index: number) => {
              Text(item).fontSize(12)
            }, (_item: string, index: number) => index.toString())
          }
          .width('100%')
        }
        .height(200)
        .backgroundColor('#F5F5F5')
        .padding(8)
      }
      .width('100%')
      .padding(12)
    }
    .height('100%')
  }
}
