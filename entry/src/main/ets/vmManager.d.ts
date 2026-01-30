declare module '@ohos.virtService.vmManager' {
  export type VmValue = string | number | boolean | null;

  export interface VmMapValue {
    [key: string]: VmValue | VmMapValue | undefined;
  }

  export type VmResult = VmValue | VmMapValue | undefined;

  export interface VmCfgInfo {
    cpuNum: number;
    memorySize: number;
    diskSize: number;
  }

  export type VmEventType = 'vmStateChange' | 'vmViewStateChange';

  export interface VmEventPayload {
    vmName?: string;
    state?: string;
    windowId?: number;
    [key: string]: VmValue | VmMapValue | undefined;
  }

  export interface VmManagerApi {
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

  const vmManager: VmManagerApi;
  export default vmManager;
}
