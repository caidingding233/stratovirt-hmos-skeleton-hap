# StratoVirt App
## 这是啥 能吃吗
这是使用华为在系统中的虚拟机服务（vm_services）服务去调用系统StratoVirt服务去使用虚拟机的App
## 构建和使用
首先 确保您获得了华为的授权
因为没有授权 您无权调用vm_services的API和任何的SDK
然后 等到你和华为谈妥了 你可以这么做
```shell
# 先下载下来
git clone https://github.com/caidingding233/stratovirt-hmos-skeleton-hap.git
```
然后呢 下载好了 用华为的[DevEco Stidio](https://developer.huawei.com/consumer/cn/deveco-studio/)打开它
再然后呢 设置一下签名 就可以用了
## 原理？你怎么变出来的？
见文档[vm_manager_integration.md](docs/vm_manager_integration.md)